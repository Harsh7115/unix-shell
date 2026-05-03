# Exit Codes

This document describes the exit-code convention the shell follows for both
its own diagnostics and the values it propagates from child processes. The
intent is to match POSIX-conforming shells (bash, dash, ksh) closely enough
that scripts written for those shells behave identically here.

## Range

Exit codes are 8-bit unsigned integers. The shell stores them as `int` in
the `last_status` global and returns the low 8 bits to the parent process.
Values are looked up via the special parameter `$?`.

## Standard codes

| Code | Meaning                                              |
|------|------------------------------------------------------|
| 0    | Success — the command (or pipeline) completed cleanly. |
| 1    | General error from a built-in or the shell itself.   |
| 2    | Misuse of a built-in. `cd: too many arguments`, etc. |
| 126  | Command found but not executable. EACCES on `exec`.  |
| 127  | Command not found in `PATH` or as a built-in.        |
| 128  | Argument out of range for `exit`. `exit -1` becomes 255. |
| 128+N| Killed by signal N. `128 + SIGINT (2)` = 130.        |
| 130  | Terminated by Ctrl-C (SIGINT).                       |
| 137  | Killed by SIGKILL (9).                               |
| 143  | Terminated by SIGTERM (15).                          |
| 255  | Generic catastrophic failure (exit out of 8-bit range). |

## How the shell computes `$?`

The relevant code lives in `src/exec.c`:

```c
int compute_status(int wait_status) {
    if (WIFEXITED(wait_status)) {
        return WEXITSTATUS(wait_status);
    }
    if (WIFSIGNALED(wait_status)) {
        return 128 + WTERMSIG(wait_status);
    }
    /* Stopped or untraced. */
    return 0;
}
```

`compute_status` is called once per foreground command and once per pipeline
component. For a pipeline, only the *last* component's status is propagated
(unless `pipefail` is set — see below).

## Pipelines

A pipeline's status is the status of the rightmost command. With `set -o
pipefail`, the status is the rightmost non-zero status, or zero if every
component succeeded.

```
$ false | true ; echo $?
0
$ set -o pipefail
$ false | true ; echo $?
1
```

## Built-in failures

Built-ins map their internal errors onto codes 1 and 2:

| Built-in   | Failure                                | Code |
|------------|----------------------------------------|------|
| `cd`       | Path does not exist                    | 1    |
| `cd`       | Too many arguments                     | 2    |
| `export`   | Invalid name                           | 1    |
| `unset`    | Read-only variable                     | 1    |
| `jobs`     | Job spec not found                     | 1    |
| `fg`/`bg` | No such job                            | 1    |
| `source`   | File not found / not readable          | 1    |
| `source`   | Syntax error in sourced file           | 2    |
| `exit`     | Bad numeric argument                   | 2    |

## Forwarding signals

When a job is killed by a signal, the shell prints a one-line message to
stderr (mimicking bash) and sets `$?` to `128 + sig`:

```
$ sleep 30 &
[1] 12345
$ kill -KILL %1
[1]+  Killed                  sleep 30
$ echo $?
137
```

Note that `SIGPIPE` (13) is silently swallowed during pipeline shutdown —
the shell does not emit a "Broken pipe" message because doing so would clutter
common idioms like `yes | head -n 1`.

## When the shell itself exits

If the shell receives `SIGHUP` while interactive, it sends `SIGHUP` to all
children and exits with code `128 + SIGHUP` = 129. `set -o huponexit` is the
default for login shells.

## See also

- `docs/job-control.md` — for how stopped jobs interact with status
- `docs/signal-handling.md` — for the trap and signal-mask discipline
