# unix-shell — Architecture

A walkthrough of how the shell is structured, how data flows through it, and
the key design decisions made along the way.

---

## Table of Contents

1. [High-level overview](#high-level-overview)
2. [Source layout](#source-layout)
3. [Read–Eval–Print loop](#readevalprintloop)
4. [Tokeniser](#tokeniser)
5. [Parser and AST](#parser-and-ast)
6. [Execution engine](#execution-engine)
7. [I/O redirection](#io-redirection)
8. [Pipes](#pipes)
9. [Job control](#job-control)
10. [Built-in commands](#built-in-commands)
11. [Signal handling](#signal-handling)
12. [Design decisions and trade-offs](#design-decisions-and-trade-offs)

---

## High-level overview

```
┌──────────────────────────────────────────────────────┐
│                    unix-shell process                │
│                                                      │
│  stdin ──► Lexer ──► Parser ──► AST                  │
│                                  │                   │
│                           ┌──────┴──────┐            │
│                           │  Executor   │            │
│                           └──┬──────────┘            │
│             built-ins ◄──────┤                       │
│             fork+exec ◄──────┤                       │
│             pipes     ◄──────┤                       │
│             redir.    ◄──────┤                       │
│             job ctrl  ◄──────┘                       │
└──────────────────────────────────────────────────────┘
```

The shell is a single-process, event-driven interpreter.  Child processes are
created with `fork(2)` + `exec(2)`; the parent waits with `waitpid(2)` for
foreground jobs and uses `SIGCHLD` reaping for background jobs.

---

## Source layout

```
unix-shell/
├── src/
│   ├── main.c          — entry point; initialises signal masks and starts REPL
│   ├── lexer.c / .h    — tokeniser: splits input into token stream
│   ├── parser.c / .h   — recursive-descent parser; builds command AST
│   ├── executor.c / .h — tree-walk executor; forks/execs leaf nodes
│   ├── builtin.c / .h  — cd, exit, jobs, fg, bg, history, export, unset
│   ├── job.c / .h      — job table, PGID management, foreground/background
│   ├── redir.c / .h    — dup2-based I/O redirection helpers
│   └── utils.c / .h    — string helpers, error wrappers (die, xmalloc, …)
├── tests/              — shell-level integration tests (runnable with make test)
├── docs/               — this directory
├── Makefile
└── README.md
```

---

## Read–Eval–Print loop

`main.c` runs an infinite loop:

```c
while (1) {
    char *line = readline(prompt());   // or fgets for non-interactive
    if (!line) break;                  // EOF → exit
    add_history(line);
    List *ast = parse(line);
    execute(ast);
    ast_free(ast);
    free(line);
}
```

Interactive mode detects `isatty(STDIN_FILENO)` and enables the prompt;
script mode silently reads from stdin or a file argument.

---

## Tokeniser

`lexer.c` consumes characters one at a time and emits a flat array of
`Token` structs:

| Token type | Examples |
|---|---|
| `TOK_WORD` | `ls`, `-la`, `"hello world"`, `$VAR` |
| `TOK_PIPE` | `|` |
| `TOK_REDIR_IN` / `OUT` / `APPEND` | `<`, `>`, `>>` |
| `TOK_AND` / `TOK_OR` | `&&`, `||` |
| `TOK_SEMI` | `;` |
| `TOK_BG` | `&` |
| `TOK_LPAREN` / `RPAREN` | `(`, `)` |
| `TOK_EOF` | end of input |

Variable expansion (`$NAME`, `${NAME}`) and tilde expansion (`~`) are
performed inline during tokenisation so the parser only ever sees plain words.

---

## Parser and AST

The parser is a hand-written recursive-descent parser.  The grammar (simplified):

```
list        ::= pipeline (('&&' | '||') pipeline)*
pipeline    ::= command ('|' command)*
command     ::= simple_cmd | subshell
simple_cmd  ::= WORD* redirection*
subshell    ::= '(' list ')' redirection*
redirection ::= ('<' | '>' | '>>') WORD
```

AST node types live in `parser.h`:

```c
typedef enum { NODE_CMD, NODE_PIPE, NODE_AND, NODE_OR, NODE_BG, NODE_SUBSHELL } NodeKind;

typedef struct ASTNode {
    NodeKind        kind;
    char          **argv;      // for NODE_CMD: NULL-terminated argument vector
    Redir          *redirs;    // linked list of redirections
    struct ASTNode *left;      // for binary operators: left child
    struct ASTNode *right;     // for binary operators: right child
} ASTNode;
```

---

## Execution engine

`executor.c` does a depth-first tree walk:

- **`NODE_CMD`** — look up in builtin table; if not found, `fork` + `execvp`.
- **`NODE_PIPE`** — create a `pipe(2)`, fork left child with stdout → write-end
  and right child with stdin → read-end, then `waitpid` both.
- **`NODE_AND`** — execute left; if exit status 0, execute right.
- **`NODE_OR`** — execute left; if exit status non-0, execute right.
- **`NODE_BG`** — fork left child, add to job table, do not wait.
- **`NODE_SUBSHELL`** — fork a child shell process, execute inner list in it.

---

## I/O redirection

Before `execvp`, `redir.c` applies the redirection list in order:

```c
for (Redir *r = node->redirs; r; r = r->next) {
    int fd = open(r->file, r->flags, 0644);
    dup2(fd, r->target_fd);   // target_fd is 0 (stdin) or 1 (stdout)
    close(fd);
}
```

Here-documents (`<<`) are implemented by writing the body to a temporary file
and redirecting stdin from it.

---

## Pipes

A pipeline of N commands uses N-1 `pipe(2)` calls set up in a loop before any
`fork`:

```
cmd1 | cmd2 | cmd3
 ↕        ↕
pipe[0]  pipe[1]
```

Each child closes the file descriptors it does not own.  The parent closes all
pipe ends after forking so `cmd3`'s EOF is correctly triggered when `cmd2`
exits.

---

## Job control

Job control follows POSIX `tcsetpgrp(3)` semantics:

1. On `fork`, the child calls `setpgid(0, 0)` to start a new process group.
2. For foreground jobs, the parent calls `tcsetpgrp(STDIN_FILENO, child_pgid)`
   to hand the terminal to the child, then `waitpid(-child_pgid, …)` to wait.
3. When the job stops (`SIGTSTP`) or finishes, the shell reclaims the terminal
   with `tcsetpgrp(STDIN_FILENO, shell_pgid)`.
4. The `jobs` builtin iterates the job table; `fg`/`bg` send `SIGCONT`.

---

## Built-in commands

| Command | File | Notes |
|---|---|---|
| `cd` | `builtin.c` | updates `$OLDPWD` |
| `exit` | `builtin.c` | optional status code |
| `jobs` | `builtin.c` | lists job table |
| `fg` / `bg` | `builtin.c` | `SIGCONT` + `tcsetpgrp` |
| `history` | `builtin.c` | prints readline history |
| `export` | `builtin.c` | calls `putenv(3)` |
| `unset` | `builtin.c` | calls `unsetenv(3)` |

Built-ins run in the shell process itself (no fork) so they can mutate the
shell's environment and working directory.

---

## Signal handling

| Signal | Handler | Reason |
|---|---|---|
| `SIGINT` | SIG_IGN in shell; delivered to fg job's pgid | Ctrl-C kills job, not shell |
| `SIGQUIT` | SIG_IGN in shell | Same rationale |
| `SIGTSTP` | SIG_IGN in shell | Ctrl-Z stops job via tty |
| `SIGCHLD` | `reap_children()` | Reap background jobs without blocking |
| `SIGTTOU` | SIG_IGN | Prevents background writes from raising SIGTTOU |

Signal masks are set in `main.c` before the REPL starts and restored to
defaults in each child after `fork` and before `exec`.

---

## Design decisions and trade-offs

| Decision | Rationale |
|---|---|
| Hand-written lexer & parser | Zero dependencies; full control over error messages |
| Flat token array vs. streaming | Simplifies backtracking in parser |
| Recursive-descent over yacc/bison | Easier to read; good enough for POSIX sh subset |
| Lazy variable expansion in lexer | Avoids a separate expansion pass; covers 95% of cases |
| Job table as a fixed-size array | Simplicity; shells rarely have >256 concurrent jobs |
| `waitpid` in `SIGCHLD` handler | Avoids zombie accumulation without blocking the REPL |
