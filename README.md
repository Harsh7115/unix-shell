# unix-shell

A POSIX-compliant Unix shell implemented from scratch in **C**, supporting the core features of a production shell.

## Features

- **Pipelines** — chain commands with `|`, correctly wiring stdout → stdin across processes
- **I/O Redirection** — `>`, `>>`, `<` for file-based input/output
- **Background Jobs** — run processes with `&` and track them
- **Signal Handling** — proper `SIGINT`, `SIGTSTP`, `SIGCHLD` handling
- **Job Control** — `fg`, `bg`, `jobs` builtins to manage stopped/background processes
- **Built-in Commands** — `cd`, `exit`, `jobs`, `fg`, `bg`
- **Process Groups** — each pipeline runs in its own process group for correct signal delivery

## Build & Run

```bash
git clone https://github.com/Harsh7115/unix-shell
cd unix-shell
make
./shell
```

## Usage Examples

```bash
# Pipeline
ls -la | grep ".c" | wc -l

# I/O redirection
cat input.txt | sort > output.txt

# Background job
sleep 10 &
jobs        # list background jobs
fg %1       # bring job 1 to foreground

# Nested pipes
cat file.txt | tr 'a-z' 'A-Z' | rev
```

## Implementation Details

- **`fork` / `execvp`** for process spawning
- **`pipe(2)`** system call for inter-process communication
- **`waitpid`** with `WNOHANG` for non-blocking child reaping
- **`tcsetpgrp`** for terminal control handoff to foreground process group
- Tokenizer handles quoted strings, escape characters, and whitespace

## Tech Stack

C · POSIX APIs · GNU Make

---

Built to understand how shells actually work — from `fork/exec` to job control and signal semantics.
