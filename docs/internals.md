# unix-shell — Internals

This document walks through the major subsystems of the shell implementation and explains how they interact. Reading the source alongside this guide should make the code easy to follow.

---

## High-level execution flow

```
main()
  └─ repl()                  // Read-Eval-Print Loop
       ├─ read_line()         // read one line from stdin (or a script file)
       ├─ tokenize()          // split into tokens, handle quoting & escaping
       ├─ parse()             // build a command tree (pipes, redirects, &&, ||)
       └─ execute()           // evaluate the tree; fork/exec leaf nodes
```

---

## 1. Tokeniser

**File:** `src/tokenize.c`

The tokeniser converts a raw input line into a flat array of `Token` structs:

```c
typedef enum {
    TOK_WORD,        // ordinary argument
    TOK_PIPE,        // |
    TOK_REDIR_IN,    // <
    TOK_REDIR_OUT,   // >
    TOK_REDIR_APPEND,// >>
    TOK_AND,         // &&
    TOK_OR,          // ||
    TOK_SEMICOLON,   // ;
    TOK_LPAREN,      // (
    TOK_RPAREN,      // )
    TOK_EOF,
} TokenType;

typedef struct {
    TokenType type;
    char     *value;  // heap-allocated, NULL for non-WORD tokens
} Token;
```

### Quoting rules

| Syntax          | Behaviour                                    |
|-----------------|----------------------------------------------|
| `'...'`          | Literal — no expansions, no backslash escape |
| `"..."`          | Variable expansion (`$VAR`) and `\$`, `\\`, `\"` |
| `\<char>`       | Escapes a single character outside quotes    |

The tokeniser is a hand-written finite automaton with states:
`NORMAL`, `IN_SINGLE_QUOTE`, `IN_DOUBLE_QUOTE`, `ESCAPE`, `COMMENT`.

---

## 2. Parser

**File:** `src/parse.c`

The parser builds a binary tree of `ASTNode` structs using a recursive-descent grammar:

```
list        := pipeline ( ('&&' | '||' | ';') pipeline )*
pipeline    := command ( '|' command )*
command     := WORD* redirect*
redirect    := ('<' | '>' | '>>') WORD
```

```c
typedef enum {
    NODE_CMD,        // leaf: execv target
    NODE_PIPE,       // binary: left | right
    NODE_AND,        // binary: left && right
    NODE_OR,         // binary: left || right
    NODE_SEQ,        // binary: left ; right
    NODE_REDIR_IN,
    NODE_REDIR_OUT,
    NODE_REDIR_APPEND,
} NodeType;

typedef struct ASTNode {
    NodeType        type;
    char          **argv;       // for NODE_CMD: NULL-terminated arg vector
    char           *redir_file; // for redirect nodes
    struct ASTNode *left;
    struct ASTNode *right;
} ASTNode;
```

The tree is heap-allocated and freed by `ast_free()` after execution.

---

## 3. Executor

**File:** `src/execute.c`

`execute(ASTNode *node)` walks the AST recursively:

### NODE_CMD — simple command

1. Check if the command is a **built-in** (`cd`, `exit`, `export`, `unset`, `echo`, `pwd`).  Built-ins run in the shell process; they must not `fork`.
2. Otherwise: `fork()` → child calls `execvp(argv[0], argv)`; parent `waitpid()`.
3. Before `execvp`, apply any redirections by duplicating file descriptors:

```c
// redirect stdout to a file
int fd = open(file, O_WRONLY | O_CREAT | O_TRUNC, 0644);
dup2(fd, STDOUT_FILENO);
close(fd);
```

### NODE_PIPE

1. `pipe(fds)` creates a read/write pair.
2. Fork **left** child → redirect its stdout to `fds[1]`, close `fds[0]`.
3. Fork **right** child → redirect its stdin from `fds[0]`, close `fds[1]`.
4. Parent closes both ends and waits for both children.

Pipelines of length N are handled recursively: each `NODE_PIPE` node connects exactly two subtrees, so a three-command pipeline `a | b | c` is represented as `PIPE(a, PIPE(b, c))`.

### NODE_AND / NODE_OR

```
AND: execute left; if exit code == 0, execute right
OR:  execute left; if exit code != 0, execute right
```

The exit code of the last executed subtree is returned upward.

---

## 4. Built-in commands

**File:** `src/builtins.c`

| Command  | Notes                                                         |
|----------|---------------------------------------------------------------|
| `cd`     | Calls `chdir()`; updates `PWD` env var; handles `-` for prev dir |
| `exit`   | Accepts optional exit code; flushes history before exiting    |
| `export` | Calls `setenv()`; supports `KEY=VALUE` and bare `KEY` form       |
| `unset`  | Calls `unsetenv()`                                            |
| `echo`   | Handles `-n` flag (suppress trailing newline)                 |
| `pwd`    | Calls `getcwd()` or reads `PWD` env var                       |

---

## 5. Signal handling

**File:** `src/signals.c`

The shell installs custom handlers for:

- **SIGINT** (Ctrl-C): interrupts the foreground job but does not kill the shell.  The REPL prints a new prompt.
- **SIGTSTP** (Ctrl-Z): suspends the foreground job (`SIGSTOP` sent to the child process group).
- **SIGCHLD**: reaped in the background to avoid zombie processes when running async commands.

Child processes inherit default signal dispositions (handlers are reset to `SIG_DFL` after `fork()` and before `execvp()`).

---

## 6. Job control (background processes)

Background commands (`cmd &`) are forked into their own **process group** via `setpgid(pid, pid)`. The parent does not wait; instead it records the job in a `jobs` table and prints `[1] <pid>`. The `SIGCHLD` handler reaps finished background jobs and prints the completion notice on the next prompt.

---

## 7. Memory management

All heap allocations go through thin wrappers (`xmalloc`, `xstrdup`) that call `abort()` on failure. The AST is freed bottom-up by `ast_free()` after each command completes. `argv` arrays inside `NODE_CMD` nodes are freed individually; their strings are sub-slices of the token array which is freed by `tokens_free()`.

---

## 8. Known limitations / future work

- **No here-documents** (`<<EOF`): the tokeniser does not handle multi-line here-docs yet.
- **No arithmetic expansion** (`$((...))`): planned.
- **No job bring-to-foreground** (`fg %1`): `jobs` table exists but `fg`/`bg` builtins are not yet implemented.
- **No command history across sessions**: `readline` history is in-memory only.
