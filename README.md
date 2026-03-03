# unix-shell

A POSIX-compliant Unix shell implemented from scratch in C. Supports the core features you'd expect from a real shell — pipes, I/O redirection, background jobs, signal handling, and a set of built-in commands.

Written as a deep dive into Unix process management, file descriptors, and the exec family of syscalls.

## Features

- **Command execution** — fork/exec with PATH resolution
- **Pipes** — arbitrary pipeline chains (`cmd1 | cmd2 | cmd3`)
- **I/O redirection** — `>`, `>>`, `<`, `2>`, `2>&1`
- **Background jobs** — `cmd &` with job table tracking
- **Job control** — `jobs`, `fg`, `bg`, `Ctrl-Z` (SIGTSTP)
- **Signal handling** — `SIGINT`, `SIGQUIT`, `SIGCHLD` handled correctly
- **Built-ins** — `cd`, `pwd`, `exit`, `export`, `unset`, `jobs`, `fg`, `bg`, `history`
- **Environment variables** — `$VAR` expansion, `export`, `unset`
- **Command history** — up/down arrow navigation (via readline)
- **Quoting** — single quotes, double quotes, backslash escaping

## Building

```bash
git clone https://github.com/Harsh7115/unix-shell
cd unix-shell
make
./hsh
```

Requires: GCC, GNU Make, readline (`sudo apt install libreadline-dev` on Ubuntu)

## Usage

```bash
# Basic command
$ ls -la

# Pipeline
$ cat /etc/passwd | grep root | cut -d: -f1

# Redirection
$ gcc main.c -o prog 2> build.log
$ ./prog < input.txt > output.txt

# Background job
$ sleep 60 &
[1] 12345

# Job control
$ jobs
[1]+ Running    sleep 60 &
$ fg 1
```

## Architecture

```
unix-shell/
├── src/
│   ├── main.c          # REPL loop, readline integration
│   ├── lexer.c         # Tokeniser (handles quoting, escaping)
│   ├── parser.c        # Builds command tree from tokens
│   ├── executor.c      # fork/exec, pipes, redirections
│   ├── builtins.c      # cd, export, jobs, fg, bg, history …
│   ├── jobs.c          # Job table, SIGCHLD handler
│   ├── signals.c       # Signal setup for interactive shell
│   └── env.c           # Environment variable management
├── include/
│   ├── shell.h         # Shared types and prototypes
│   └── jobs.h
├── tests/
│   └── run_tests.sh    # Integration tests
├── Makefile
└── README.md
```

## Implementation Notes

- Uses `waitpid(WNOHANG)` in the SIGCHLD handler to reap background children without blocking
- Pipes are built left-to-right: each stage creates a `pipe(2)` pair, the left child writes to `pipefd[1]` and the right reads from `pipefd[0]`
- The shell forks a separate **process group** for each pipeline so `Ctrl-C` only kills the foreground job, not the shell itself
- Readline callbacks set the terminal back to canonical mode before exec so child processes see a normal tty

## Running Tests

```bash
make test
```

## License

MIT
