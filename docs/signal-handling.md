# Signal Handling in hsh

Correct signal handling is one of the trickiest parts of writing a POSIX shell.
This document explains how `hsh` sets up, delivers, and resets signals at each
stage of the process lifecycle.

---

## Why Signals Are Complicated in a Shell

A shell must manage signals across (at least) three distinct execution contexts:

1. **The interactive shell itself** — must survive Ctrl-C and Ctrl-Z without dying.
2. **Foreground child processes** — must receive SIGINT/SIGTSTP and act on them.
3. **Background child processes** — must not be affected by terminal signals at all.

Getting the dispositions wrong in any context causes subtle bugs:
pressing Ctrl-C kills the shell instead of the job, or child processes silently
ignore SIGINT because the parent's `SIG_IGN` is inherited across `fork()`.

---

## Signal Disposition Table

| Signal | Interactive shell | Foreground child | Background child |
|--------|------------------|-----------------|-----------------|
| SIGINT | SIG_IGN | SIG_DFL | SIG_IGN |
| SIGQUIT | SIG_IGN | SIG_DFL | SIG_IGN |
| SIGTSTP | SIG_IGN | SIG_DFL | SIG_IGN |
| SIGCHLD | shell_sigchld_handler | SIG_DFL | SIG_DFL |
| SIGTTOU | SIG_IGN | SIG_DFL | SIG_DFL |
| SIGTTIN | SIG_IGN | SIG_DFL | SIG_DFL |
| SIGTERM | SIG_DFL | SIG_DFL | SIG_DFL |

---

## Initialisation (`signals.c:shell_init_signals()`)

Called once at startup, before the REPL loop begins:

```c
void shell_init_signals(void) {
    struct sigaction sa_ign = { .sa_handler = SIG_IGN };
    sigemptyset(&sa_ign.sa_mask);

    /* Ignore job-control signals in the shell process */
    sigaction(SIGINT,  &sa_ign, NULL);
    sigaction(SIGQUIT, &sa_ign, NULL);
    sigaction(SIGTSTP, &sa_ign, NULL);
    sigaction(SIGTTIN, &sa_ign, NULL);
    sigaction(SIGTTOU, &sa_ign, NULL);

    /* Install SIGCHLD handler for background job reaping */
    struct sigaction sa_chld = {
        .sa_handler = shell_sigchld_handler,
        .sa_flags   = SA_RESTART | SA_NOCLDSTOP,
    };
    sigemptyset(&sa_chld.sa_mask);
    sigaction(SIGCHLD, &sa_chld, NULL);
}
```

`SA_RESTART` causes interrupted system calls (e.g. `read` inside `readline`) to
be automatically restarted rather than returning `EINTR`. This avoids spurious
errors in the REPL when a background job exits mid-keystroke.

`SA_NOCLDSTOP` tells the kernel to only deliver SIGCHLD when a child **exits**,
not when it stops — we handle stops separately via `WUNTRACED` in `waitpid`.

---

## Child Setup (`signals.c:shell_prep_child()`)

Called in the child process **after `fork()` but before `execvp()`**:

```c
void shell_prep_child(void) {
    struct sigaction sa_dfl = { .sa_handler = SIG_DFL };
    sigemptyset(&sa_dfl.sa_mask);

    sigaction(SIGINT,  &sa_dfl, NULL);
    sigaction(SIGQUIT, &sa_dfl, NULL);
    sigaction(SIGTSTP, &sa_dfl, NULL);
    sigaction(SIGTTIN, &sa_dfl, NULL);
    sigaction(SIGTTOU, &sa_dfl, NULL);
    sigaction(SIGCHLD, &sa_dfl, NULL);
}
```

This is **mandatory**. POSIX specifies that `fork()` inherits signal dispositions,
so without this reset, child processes would inherit `SIG_IGN` for SIGINT.
The user would then be unable to kill a runaway foreground job with Ctrl-C.

Importantly, `execvp()` automatically resets all signals with custom handlers
(`sa_handler != SIG_IGN`) back to `SIG_DFL`. However, `SIG_IGN` dispositions
**survive `exec`** — which is exactly why we reset them explicitly beforehand.

---

## SIGCHLD Handler — Reaping Background Jobs

```c
static void shell_sigchld_handler(int sig) {
    (void)sig;
    int saved_errno = errno;   /* handlers must preserve errno */

    pid_t pid;
    int   status;
    while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
        job_t *j = job_find_pid(pid);
        if (!j) continue;

        if (WIFEXITED(status) || WIFSIGNALED(status)) {
            j->state = JOB_DONE;
            j->exit_status = WIFEXITED(status)
                           ? WEXITSTATUS(status)
                           : 128 + WTERMSIG(status);
        }
    }

    errno = saved_errno;
}
```

Key points:

- `waitpid(-1, ..., WNOHANG)` reaps **any** finished child without blocking.
  The `while` loop handles the case where multiple children exit simultaneously.
- The handler is **async-signal-safe**: it uses only `waitpid`, pointer reads/writes
  and integer arithmetic — no `malloc`, `printf`, or locks.
- `errno` is saved and restored because signal handlers can interrupt any syscall
  and corrupt the caller's `errno` if we do not.
- Printing `[N]+ Done` is deferred to the next prompt render, not done in the
  handler, to avoid calling non-async-signal-safe I/O functions.

---

## Foreground Job Terminal Control

When a foreground pipeline is launched, the shell gives the terminal to the
child's process group so that Ctrl-C/Ctrl-Z are delivered to the job, not the shell:

```c
/* In parent, after fork */
setpgid(pid, pid);                         /* new process group       */
if (!job->background)
    tcsetpgrp(STDIN_FILENO, pid);          /* hand over the terminal  */

/* Wait — WUNTRACED catches Ctrl-Z stops */
waitpid(-job->pgid, &status, WUNTRACED);

/* Reclaim terminal when the job finishes or stops */
tcsetpgrp(STDIN_FILENO, shell_pgid);
```

`SIGTTOU` is ignored in the shell so that `tcsetpgrp()` does not generate a
signal when called from a background context (e.g. inside a subshell pipeline).

---

## Background Jobs and Terminal Signals

Background jobs must not receive SIGINT or SIGTSTP from the terminal.
This is guaranteed by two mechanisms working together:

1. **Process group isolation** — background jobs are placed in their own pgrp
   (`setpgid(pid, pid)`). Terminal signals (SIGINT, SIGTSTP) are delivered only
   to the **foreground process group** of the controlling terminal. Background
   pgrps never receive them automatically.

2. **SIG_IGN inheritance safety** — the child resets SIGINT/SIGTSTP to `SIG_DFL`
   (`shell_prep_child()`) before `exec`. If a background program explicitly
   ignores SIGINT, that is its own choice; the shell does not interfere.

---

## Ctrl-Z (SIGTSTP) and Job Resumption

When the user presses Ctrl-Z while a foreground job is running:

```
Terminal driver  ->  SIGTSTP  ->  foreground pgrp (the job)
                                  (shell has SIG_IGN, is unaffected)
Job stops  ->  WIFSTOPPED in waitpid  ->  shell marks job as JOB_STOPPED
Shell reclaims terminal (tcsetpgrp back to shell_pgid)
Shell prints: "[1]+ Stopped   sleep 30"
```

Resuming with `fg N`:
```c
tcsetpgrp(STDIN_FILENO, job->pgid);   /* give terminal back to job  */
kill(-job->pgid, SIGCONT);            /* wake the stopped pgrp      */
waitpid(-job->pgid, &st, WUNTRACED); /* wait again                 */
tcsetpgrp(STDIN_FILENO, shell_pgid);  /* reclaim on completion      */
```

Resuming with `bg N`:
```c
kill(-job->pgid, SIGCONT);   /* wake the pgrp, do NOT wait */
job->state = JOB_RUNNING;    /* mark running in background */
```

---

## Common Signal Bugs and How hsh Avoids Them

| Bug | Cause | hsh fix |
|-----|-------|---------|
| Ctrl-C kills the shell | Shell does not ignore SIGINT | `shell_init_signals()` sets SIG_IGN |
| Child ignores Ctrl-C | SIG_IGN inherited across fork | `shell_prep_child()` resets to SIG_DFL |
| Zombie background jobs | No SIGCHLD handler | `SA_RESTART` SIGCHLD handler calls `waitpid(WNOHANG)` |
| `readline` breaks on SIGCHLD | EINTR not restarted | `SA_RESTART` flag on SIGCHLD handler |
| Race: child exits before `setpgid` | Fork/setpgid race | Both parent AND child call `setpgid(pid,pid)` |
| SIGTTOU stops the shell on `tcsetpgrp` | Shell in background pgrp | Shell ignores SIGTTOU |
