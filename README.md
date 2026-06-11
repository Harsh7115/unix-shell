# unix-shell

A POSIX-compliant Unix shell written from scratch in C — pipes, I/O redirection, job control, and signal handling, all built on raw `fork`/`exec`/`wait` primitives.

## Features

| Feature | Details |
|---|---|
| Pipelines | `cmd1 \| cmd2 \| cmd3` — `stdout` of each stage wired to `stdin` of the next |
| I/O Redirection | `>` overwrite, `>>` append, `<` input from file |
| Background Jobs | `cmd &` — tracked by job ID, listed with `jobs` |
| Job Control | `fg %N`, `bg %N` — move jobs between foreground and background |
| Signal Handling | `SIGINT` (Ctrl-C), `SIGTSTP` (Ctrl-Z), `SIGCHLD` (child reaping) |
| Built-ins | `cd`, `exit`, `jobs`, `fg`, `bg` |
| Process Groups | Each pipeline gets its own pgid for correct signal delivery |

## Build & Run

```bash
git clone https://github.com/Harsh7115/unix-shell
cd unix-shell
make
./shell
```

## Usage

```bash
# Multi-stage pipeline
ls -la | grep ".c" | wc -l

# I/O redirection
sort < input.txt > sorted.txt
cat log.txt >> archive.txt

# Background job + control
sleep 60 &           # [1] 4821
jobs                 # [1]+ Running   sleep 60
fg %1                # bring to foreground
# Ctrl-Z             # suspend it
bg %1                # resume in background

# Nested pipes
cat file.txt | tr 'a-z' 'A-Z' | rev
```

## How It Works

### Command lifecycle

```
Input string
    │
    ▼
Tokenizer          quoted strings, whitespace, metachar splitting
    │
    ▼
Parser             builds pipeline: [ cmd1 | cmd2 | cmd3 ]
    │
    ▼
Executor
  ├── for each stage: fork() → child calls execvp()
  ├── pipe(2) connects adjacent stages
  ├── dup2(2) wires stdin/stdout to pipe ends
  ├── parent calls setpgid() to assign pipeline to a process group
  └── tcsetpgrp() hands terminal control to foreground pgid
    │
    ▼
Reaper             waitpid(WNOHANG) in SIGCHLD handler, updates job table
```

### Signal handling

| Signal | Source | Shell behavior |
|---|---|---|
| `SIGINT` | Ctrl-C | Forwarded to foreground process group; shell ignores it |
| `SIGTSTP` | Ctrl-Z | Stops foreground process group; shell marks job STOPPED |
| `SIGCHLD` | Child exit/stop | `waitpid` loop reaps zombies, updates job state |
| `SIGTTOU` | Background write to tty | Ignored by shell to prevent self-stops |

### Process groups and terminal control

Every pipeline runs in its own process group. `tcsetpgrp()` grants the terminal to the foreground pgid, so `SIGINT`/`SIGTSTP` only reach the running job — not the shell itself. When the job finishes or is suspended, `tcsetpgrp()` returns control to the shell's pgid.

## Source Structure

```
unix-shell/
├── shell.c          # REPL loop, prompt, readline
├── tokenizer.c/h    # Lexer: splits input into tokens, handles quoting
├── parser.c/h       # Builds pipeline structs from token stream
├── executor.c/h     # fork/exec, pipe wiring, pgid management
├── jobs.c/h         # Job table: add, update, print, reap
├── builtins.c/h     # cd, exit, jobs, fg, bg
├── signals.c/h      # Signal handler setup and dispatch
└── Makefile
```

## Implementation Notes

- `waitpid(-1, WNOHANG, WUNTRACED)` in the `SIGCHLD` handler reaps all finished children without blocking
- `dup2` is called in the child after `fork` but before `execvp` to redirect file descriptors before the process image is replaced
- The tokenizer handles single/double quotes and backslash escapes before the parser sees any input
- Built-ins are checked before `execvp` because they need to run inside the shell process (e.g. `cd` must change the shell's own cwd)

## Tech Stack

C · POSIX APIs (`fork`, `execvp`, `pipe`, `dup2`, `waitpid`, `tcsetpgrp`, `sigaction`) · GNU Make
