# unix-shell Internals

This document describes the internal architecture of the unix-shell project — a POSIX-compliant Unix shell written in C.

## Overview

The shell is structured as a classic read-eval-print loop (REPL) with four distinct stages:

1. **Lexing** — tokenize raw input into words and operators
2. **Parsing** — build a command tree (pipelines, redirections, compound commands)
3. **Expansion** — perform variable/glob/tilde expansion
4. **Execution** — fork/exec processes, set up pipes and redirections

---

## Source Layout

```
unix-shell/
├── src/
│   ├── main.c          # Entry point, REPL loop, signal setup
│   ├── lexer.c / lexer.h       # Tokenizer
│   ├── parser.c / parser.h     # Recursive-descent parser → AST
│   ├── expand.c / expand.h     # Variable, glob, tilde, command substitution
│   ├── exec.c / exec.h         # Fork/exec, pipeline plumbing, redirections
│   ├── builtins.c / builtins.h # cd, exit, export, unset, jobs, fg, bg
│   ├── jobs.c / jobs.h         # Job control table, SIGCHLD handler
│   └── utils.c / utils.h       # String helpers, error reporting
├── tests/
│   ├── run_tests.sh    # Shell-level integration tests
│   └── *.sh            # Individual test cases
├── Makefile
└── README.md
```

---

## Lexer

The lexer (`lexer.c`) converts a raw input line into a flat list of `Token` structs.

```c
typedef enum {
    TOK_WORD,       // any unquoted or quoted word
    TOK_PIPE,       // |
    TOK_REDIR_IN,   // <
    TOK_REDIR_OUT,  // >
    TOK_REDIR_APP,  // >>
    TOK_REDIR_ERR,  // 2>
    TOK_SEMI,       // ;
    TOK_AMP,        // &  (background)
    TOK_AND,        // && (logical and)
    TOK_OR,         // || (logical or)
    TOK_LPAREN,     // ( (subshell)
    TOK_RPAREN,     // )
    TOK_EOF,
} TokenType;

typedef struct {
    TokenType type;
    char     *value;  // heap-allocated, caller must free
    int       quoted; // was this token double/single quoted?
} Token;
```

Key rules:
- Single quotes suppress all expansion.
- Double quotes suppress word-splitting and globbing, but allow `$` and backtick substitution.
- Backslash escapes the immediately following character.

---

## Parser

`parser.c` implements a hand-written recursive descent parser that produces an Abstract Syntax Tree (AST).

### Grammar (simplified)

```
list        := pipeline ( ('&&' | '||') pipeline )*
pipeline    := command ( '|' command )*
command     := simple_cmd | compound_cmd
simple_cmd  := WORD+ redirect*
redirect    := REDIR_IN WORD | REDIR_OUT WORD | REDIR_APP WORD
compound    := '(' list ')' | '{' list '}'
```

### AST Node Types

```c
typedef enum {
    NODE_CMD,       // simple command + argv
    NODE_PIPE,      // left | right
    NODE_AND,       // left && right
    NODE_OR,        // left || right
    NODE_SEQ,       // left ; right
    NODE_BG,        // command &
    NODE_REDIR,     // command with redirections
    NODE_SUBSHELL,  // ( list )
} NodeType;
```

---

## Expansion

Expansion happens after parsing but before execution (`expand.c`). The order follows POSIX §2.6:

1. **Tilde expansion** — `~` → `$HOME`
2. **Parameter expansion** — `$VAR`, `${VAR:-default}`, `${#VAR}`, `${VAR#pat}`, etc.
3. **Command substitution** — `$(...)` or `` `...` ``
4. **Arithmetic expansion** — `$((expr))`
5. **Word splitting** — split on `$IFS`
6. **Pathname expansion (globbing)** — `*`, `?`, `[...]`
7. **Quote removal**

---

## Execution

### Simple Commands

1. Check if the command is a **built-in** (`cd`, `exit`, `export`, …). If so, call the built-in handler directly in the current process.
2. Otherwise, `fork()` a child.
3. In the child: set up redirections (`dup2`), restore default signal handlers, then `execvp()`.
4. In the parent: if foreground, `waitpid()`; if background, record in the job table.

### Pipelines

A pipeline of *n* commands requires *n − 1* `pipe()` pairs. Each child process in the pipeline:
- Dups the read end of the previous pipe onto stdin
- Dups the write end of the current pipe onto stdout
- Closes all extra pipe fds before `exec`

### Job Control

Job control requires the shell to run in its own process group. Key points:
- On startup the shell calls `setpgid(0, 0)` and grabs the terminal with `tcsetpgrp`.
- Each foreground pipeline gets its own process group (`setpgid` before `exec`).
- `SIGCHLD` is caught to reap background jobs and update the job table.
- `fg` sends `SIGCONT` and gives the terminal back; `bg` sends `SIGCONT` and leaves the terminal with the shell.

---

## Built-in Commands

| Command | Notes |
|---------|-------|
| `cd [dir]` | Changes `$PWD`; updates `$OLDPWD` |
| `exit [n]` | Exits with status *n* (default last exit status) |
| `export VAR[=val]` | Marks variable for export to child environments |
| `unset VAR` | Removes a variable or function |
| `jobs` | Lists background jobs |
| `fg [%n]` | Brings job *n* to foreground |
| `bg [%n]` | Resumes job *n* in the background |
| `echo` | Prints arguments (supports `-n`, `-e`) |
| `type` | Reports whether a name is a built-in, function, or file |

---

## Signal Handling

| Signal | Shell behavior |
|--------|---------------|
| `SIGINT` | Ignored in the shell main loop; delivered to foreground job |
| `SIGQUIT` | Ignored in the shell |
| `SIGTSTP` | Ignored in the shell; stops foreground job |
| `SIGCHLD` | Caught — reaps zombies and updates the job table |
| `SIGHUP` | On login shell exit, forward to all jobs then exit |

---

## Error Handling

All syscall errors are reported via `perror()` or a custom `die()` helper that prints to stderr and exits. The shell follows the POSIX convention of exit status 127 for "command not found" and 126 for "permission denied".

---

## Testing

Integration tests live in `tests/`. Run them with:

```bash
make test
```

Each `.sh` test script launches the shell binary, feeds it input, and diffs stdout/stderr against expected output files (`.expected`).

---

## Future Work

- [ ] Here-documents (`<<EOF`)
- [ ] Extended globbing (`extglob`)
- [ ] Shell functions and `local` variables
- [ ] History expansion (`!`, `!!`)
- [ ] Readline integration for better interactive line editing
