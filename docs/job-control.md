# Job Control Implementation

This document explains how job control — background processes, foreground/background switching, and job status reporting — is implemented in the shell.

---

## 1. What Is Job Control?

Job control is the ability to:
- Run commands in the **background** (`cmd &`)
- Suspend the foreground process (`Ctrl-Z`)
- Resume a stopped job in the **foreground** (`fg [%job]`)
- Resume a stopped job in the **background** (`bg [%job]`)
- List all active jobs (`jobs`)

POSIX specifies job control behaviour in detail; this shell implements the relevant subset (POSIX.1-2017 §2.9.3).

---

## 2. Process Groups and the Terminal

### Terminal ownership
At any moment, exactly one **process group** holds the terminal's foreground role. Only processes in the foreground process group receive keyboard signals (`SIGINT`, `SIGTSTP`, `SIGHUP`). All other process groups are background and get `SIGTTIN`/`SIGTTOU` if they try to read/write the terminal.

### Shell's own process group
When the shell starts, it places itself in its own process group and takes the terminal:

```c
/* Ensure shell is session leader */
pid_t shell_pgid = getpid();
if (setpgid(shell_pgid, shell_pgid) < 0) {
    /* already a process group leader — OK */
}
tcsetpgrp(STDIN_FILENO, shell_pgid);

/* Ignore job-control signals in the shell itself */
signal(SIGTTOU, SIG_IGN);
signal(SIGTTIN, SIG_IGN);
signal(SIGTSTP, SIG_IGN);
```

The shell ignores `SIGTSTP` so that `Ctrl-Z` suspends the *foreground child*, not the shell.

---

## 3. The Job Table

Each launched pipeline is tracked as a **job**:

```c
typedef enum {
    JOB_RUNNING,
    JOB_STOPPED,
    JOB_DONE,
} job_status_t;

typedef struct process {
    pid_t           pid;
    int             status;      /* last waitpid status  */
    bool            completed;
    bool            stopped;
    char           *argv0;       /* for display          */
    struct process *next;
} process_t;

typedef struct job {
    int          jid;            /* 1-based job ID       */
    pid_t        pgid;           /* process group ID     */
    job_status_t status;
    bool         foreground;
    char        *cmdline;        /* original command text */
    process_t   *procs;          /* linked list of procs  */
    struct job  *next;
} job_t;

static job_t *job_list = NULL;   /* head of job list     */
static int    next_jid  = 1;
```

---

## 4. Launching a Pipeline

When the user enters a command (or `cmd &`):

1. **Fork** each process in the pipeline.
2. In the **child**: call `setpgid(0, pgid)` to join / create the pipeline's process group. The first child's PID becomes the PGID.
3. In the **parent**: also call `setpgid(child_pid, pgid)` (race-free double-set).
4. If **foreground**: call `tcsetpgrp(STDIN_FILENO, pgid)` to give the terminal to the new group, then wait.
5. If **background**: add to job table, print `[jid] pid`, and return immediately.

```c
static void launch_job(job_t *job, bool foreground) {
    process_t *p;
    pid_t pid;
    int pipe_fds[2], prev_fd = -1;

    for (p = job->procs; p != NULL; p = p->next) {
        if (p->next) pipe(pipe_fds);     /* not last: create pipe */

        pid = fork();
        if (pid == 0) {
            /* --- child --- */
            setpgid(0, job->pgid ? job->pgid : getpid());
            /* restore default signal handlers */
            signal(SIGINT,  SIG_DFL);
            signal(SIGTSTP, SIG_DFL);
            signal(SIGTTOU, SIG_DFL);
            /* wire up stdio from pipe fds */
            setup_io(p, prev_fd, p->next ? pipe_fds[1] : -1);
            execvp(p->argv[0], p->argv);
            perror(p->argv[0]);
            exit(127);
        }
        /* --- parent --- */
        p->pid = pid;
        if (job->pgid == 0) job->pgid = pid;
        setpgid(pid, job->pgid);   /* double-set for race safety */

        if (prev_fd >= 0) close(prev_fd);
        if (p->next)      close(pipe_fds[1]);
        prev_fd = p->next ? pipe_fds[0] : -1;
    }

    add_job(job);

    if (foreground) {
        tcsetpgrp(STDIN_FILENO, job->pgid);
        wait_for_job(job);
        tcsetpgrp(STDIN_FILENO, shell_pgid);   /* reclaim terminal */
    } else {
        printf("[%d] %d\n", job->jid, job->pgid);
    }
}
```

---

## 5. Waiting and Reaping

`wait_for_job()` loops on `waitpid(-pgid, &status, WUNTRACED)`:
- `WUNTRACED` causes `waitpid` to return when a child is **stopped**, not just terminated.
- If `WIFSTOPPED(status)`: mark the process stopped; if all procs are stopped, mark job stopped.
- If `WIFEXITED` or `WIFSIGNALED`: mark the process completed.
- Loop until all processes in the job are either completed or stopped.

Background and stopped job reaping is handled by a `SIGCHLD` handler that calls `waitpid(-1, &status, WNOHANG | WUNTRACED)` in a loop.

---

## 6. Built-in Commands

### `fg [%job]`
1. Look up the job by job ID (or default to the most recent stopped/background job).
2. Send `SIGCONT` to the process group: `kill(-job->pgid, SIGCONT)`.
3. Call `tcsetpgrp(STDIN_FILENO, job->pgid)` to give it the terminal.
4. Mark job as running and call `wait_for_job()`.
5. Reclaim terminal: `tcsetpgrp(STDIN_FILENO, shell_pgid)`.

### `bg [%job]`
1. Look up the stopped job.
2. Send `SIGCONT`: `kill(-job->pgid, SIGCONT)`.
3. Mark job as running (background).
4. Print `[jid]+ cmd &`.

### `jobs`
Iterate over `job_list`, printing each job's JID, status, and command line:
```
[1]  Running    sleep 100 &
[2]+ Stopped    vim notes.txt
```
The `+` marker indicates the "current" job (most recently stopped or backgrounded); `-` marks the previous current job.

---

## 7. Cleanup on Exit

When the shell exits, it sends `SIGHUP` to all remaining background process groups:
```c
for (job_t *j = job_list; j != NULL; j = j->next) {
    if (j->status != JOB_DONE)
        kill(-j->pgid, SIGHUP);
}
```
This matches the behaviour of login shells specified in POSIX.

---

## 8. Edge Cases and Gotchas

- **Race between parent and child `setpgid`**: both sides call `setpgid` because it is not atomic. Whichever runs first wins; the other call is a no-op (EACCES or EPERM, both ignored).
- **Orphaned process groups**: if the shell's terminal process group is no longer a child of the shell (e.g., after `exec`), `tcsetpgrp` may fail with `EPERM`. The shell logs and ignores this.
- **`SIGTTOU` on background write**: background processes that attempt `write(STDOUT_FILENO, ...)` when connected to the terminal receive `SIGTTOU`. They are suspended until brought to the foreground.
- **Interactive vs. non-interactive**: job control is only enabled when the shell is running interactively (stdin is a tty). Script mode skips all `setpgid`/`tcsetpgrp` calls.
