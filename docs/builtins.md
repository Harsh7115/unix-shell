# Built-in Commands Reference

This document describes every built-in command implemented directly in the
shell process (i.e. commands that do **not** fork a child). Built-ins are
necessary when the command must affect the shell's own state — the current
working directory, environment variables, or the job table.

---

## cd — change working directory

```
cd [dir]
cd -
```

| Argument | Behaviour |
|----------|-----------|
| *(none)* | Change to `$HOME`. |
| `dir`    | Change to `dir`. Relative paths resolved against `$PWD`. |
| `-`      | Change to previous directory (`$OLDPWD`) and print the new path. |

On success `$PWD` and `$OLDPWD` are updated. On failure an error message
is printed and the exit status is set to 1.

**Implementation note:** uses `chdir(2)`; the shell updates `PWD` itself
rather than relying on the kernel because POSIX requires `$PWD` to track
logical (symlink-preserving) paths.

---

## echo — write arguments to stdout

```
echo [-n] [arg ...]
```

Writes each `arg` separated by a single space, followed by a newline.

| Flag | Behaviour |
|------|-----------|
| `-n` | Suppress the trailing newline. |

Escape sequences (e.g. `\n`, `\t`) are **not** interpreted; use
`printf` for formatted output.

---

## exit — terminate the shell

```
exit [status]
```

Exits the shell with the given integer `status` (default: exit status of
the last foreground command). Before exiting, the shell flushes stdio.

---

## export — set or mark environment variables

```
export name[=value] ...
export -p
```

Marks each `name` for export to the environment of subsequently executed
commands. If `=value` is supplied the variable is also assigned.

`export -p` prints all currently exported variables in a form suitable
for re-reading by the shell.

**Implementation note:** calls `putenv(3)` / `setenv(3)` so that the
updated environment is inherited by forked children without extra work.

---

## unset — remove variables or functions

```
unset [-v] name ...
unset -f name ...
```

| Flag | Removes |
|------|---------|
| `-v` (default) | Shell variable and its export mark. |
| `-f`           | Shell function. |

Unsetting a read-only variable is an error.

---

## pwd — print working directory

```
pwd [-L | -P]
```

| Flag | Behaviour |
|------|-----------|
| `-L` (default) | Logical path — uses `$PWD`, preserving symlinks. |
| `-P`           | Physical path — resolves all symlinks via `getcwd(3)`. |

---

## jobs — list active jobs

```
jobs [-l] [-p]
```

Lists all jobs in the current session's job table.

| Flag | Extra output |
|------|-------------|
| `-l` | Include PID alongside the job number. |
| `-p` | Print only PIDs (one per line). |

Output format:

```
[1]+  Running    sleep 60 &
[2]-  Stopped    vim notes.txt
```

The `+` marker indicates the *current* job; `-` marks the *previous* job.

---

## fg — bring a job to the foreground

```
fg [%job]
```

Moves `%job` (default: current job) to the foreground and sends `SIGCONT`
if the process group is stopped. The shell waits for the job to finish
or stop again.

---

## bg — resume a stopped job in the background

```
bg [%job ...]
```

Sends `SIGCONT` to each specified job and marks it as a background job.
The shell does not wait for background jobs.

---

## kill — send a signal to a process or job

```
kill [-signal] pid|%job ...
kill -l [signal]
```

Built-in `kill` lets signals be sent to process groups by job spec
(e.g. `kill %1`) even when the external binary is unavailable.

| Form | Behaviour |
|------|-----------|
| `-signal` | Signal name (`HUP`, `TERM`, `KILL`, …) or number. Default: `TERM`. |
| `-l`      | List all signal names. |

---

## true / false — fixed exit status

```
true
false
```

`true` always exits 0; `false` always exits 1. Built-ins so they work
even if `/bin` is not mounted.

---

## : — null command

```
: [arg ...]
```

Does nothing; always succeeds (exit 0). Arguments are evaluated but
results are discarded. Useful as a no-op placeholder:

```sh
while :; do   # infinite loop
    sleep 1
done
```

---

## type — describe how a name is interpreted

```
type name ...
```

Prints whether each `name` is a built-in, function, alias, or external
binary located via `$PATH`.

```
$ type cd
cd is a shell builtin
$ type ls
ls is /bin/ls
```

---

## Exit-status conventions

All built-ins follow POSIX exit-status conventions:

| Status | Meaning |
|--------|---------|
| 0 | Success |
| 1 | General error (bad argument, permission denied, …) |
| 2 | Misuse of built-in (wrong number of args, unknown flag) |

A built-in that receives an invalid option prints a usage message to
*stderr* and exits with status 2.
