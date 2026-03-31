# Readline Integration in hsh

hsh uses **GNU Readline** for interactive line editing, command history,
and tab completion.  This document explains how readline is initialised,
how it interacts with signal handling and job control, and the pitfalls
to watch out for when embedding it in a shell.

---

## Why readline matters for a shell

A bare `read(2)` call gives you a simple line buffer with no editing
capabilities.  GNU Readline adds:

- Emacs / vi keybindings (left/right, Ctrl-A, Ctrl-E, Ctrl-K, …)
- Persistent history across sessions (`~/.hsh_history`)
- Programmable tab completion
- Multi-line editing with backslash continuation
- Correct terminal mode management (raw → cooked transitions)

---

## Initialisation

`src/main.c` calls the following during startup:

```c
/* 1. Tell readline the application name (used for ~/.inputrc conditionals) */
rl_readline_name = "hsh";

/* 2. Register a custom completion function */
rl_attempted_completion_function = hsh_completion;

/* 3. Load history from disk */
using_history();
read_history(history_path());   /* ~/.hsh_history */

/* 4. Set the maximum history size kept in memory */
stifle_history(HSH_HISTORY_MAX);  /* default: 1000 entries */
```

### History file path

```c
static const char *history_path(void) {
    static char path[PATH_MAX];
    const char *home = getenv("HOME");
    if (!home) home = "/tmp";
    snprintf(path, sizeof(path), "%s/.hsh_history", home);
    return path;
}
```

On clean exit (via the `exit` built-in or EOF) the shell writes history
back with `write_history(history_path())`.

---

## The REPL read loop

```c
char *line;
while ((line = readline(build_prompt())) != NULL) {
    if (*line) {                        /* skip blank lines */
        add_history(line);
        process_line(line);
    }
    free(line);                         /* readline heap-allocates each line */
}
/* EOF (Ctrl-D) falls through here */
builtin_exit(NULL);
```

Key points:

- **Prompt** is rebuilt on every iteration so it reflects the current
  directory, last exit status, and git branch (if enabled).
- **`add_history`** is called only for non-empty lines; duplicates are
  suppressed by setting `history_write_duplicates = 0` in `~/.inputrc`.
- The returned `line` is always freed — readline allocates it with
  `malloc`.

---

## Signal interaction

This is the most delicate part of the readline integration.

### SIGINT (Ctrl-C)

When the user presses Ctrl-C at the readline prompt, readline's internal
SIGINT handler fires first: it clears the current input line and redraws
the prompt.  hsh installs its own handler *after* readline initialises so
it chains correctly:

```c
/* signals.c */
static void sigint_readline(int sig) {
    (void)sig;
    rl_free_line_state();       /* discard partial input */
    rl_cleanup_after_signal();
    write(STDOUT_FILENO, "\n", 1);
    rl_reset_after_signal();
    /* longjmp back to the top of the REPL instead of exiting */
    siglongjmp(repl_jmp, 1);
}
```

The `siglongjmp` target is set with `sigsetjmp` at the top of the REPL
loop so Ctrl-C at the prompt returns cleanly to a fresh prompt rather
than terminating the shell.

### SIGTSTP (Ctrl-Z)

hsh ignores SIGTSTP for itself (`SIG_IGN`) so the shell cannot be
accidentally suspended at the readline prompt.  Child processes restore
default SIGTSTP disposition before `exec`.

### SIGWINCH (terminal resize)

Readline handles SIGWINCH internally to reflow the line being edited
across the new terminal width.  hsh does not need to do anything extra.

---

## Terminal modes

Readline switches the terminal to *raw mode* while reading input so it
can intercept individual keystrokes.  Before `fork`ing a child, the
executor must restore canonical mode so the child sees a normal tty:

```c
/* executor.c — called in the child after fork, before exec */
static void restore_terminal(void) {
    rl_deprep_terminal();   /* switch tty back to cooked mode */
}
```

After the foreground child exits / stops and control returns to the REPL,
readline calls `rl_prep_terminal` (internally, via the next `readline()`
call) to re-enter raw mode.

If this step is skipped, child programs that read from stdin (e.g.
`cat`, `less`, interactive Python) will see garbled input because the
tty is still in readline's raw mode.

---

## Tab completion

hsh registers `hsh_completion` as readline's attempted-completion
callback:

```c
static char **hsh_completion(const char *text, int start, int end) {
    (void)end;
    rl_attempted_completion_over = 1;   /* suppress default filename completion */

    if (start == 0)
        /* completing the command name — search $PATH */
        return rl_completion_matches(text, command_generator);
    else
        /* completing an argument — fall back to filename completion */
        return rl_completion_matches(text, rl_filename_completion_function);
}

static char *command_generator(const char *text, int state) {
    static DIR  *dir;
    static char *path_copy;
    static char *segment;
    /* ... iterates over directories in $PATH, returns matches ... */
}
```

**`rl_attempted_completion_over = 1`** is important: without it, readline
falls back to its own filename completer for every unmatched attempt,
which is usually wrong for the first word of a command.

---

## History search

Readline's built-in reverse incremental search (Ctrl-R) works without
any extra code.  hsh also wires up the `history` built-in which prints
the in-memory list:

```c
int builtin_history(cmd_t *cmd) {
    HIST_ENTRY **list = history_list();
    if (!list) return 0;
    int base = history_base;
    for (int i = 0; list[i]; i++)
        printf("%5d  %s\n", base + i, list[i]->line);
    return 0;
}
```

---

## Common pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Not calling `rl_deprep_terminal` before fork | Child stdin garbled | Call `rl_deprep_terminal()` in child before exec |
| Calling `add_history` on empty string | Extra blank entries | Guard with `if (*line)` |
| Not freeing readline's return value | Memory leak per command | Always `free(line)` |
| Forgetting `rl_free_line_state` on SIGINT | Partial line persists | Call in SIGINT handler |
| Using `readline` in non-interactive mode | Hangs on piped input | Check `isatty(STDIN_FILENO)`; use `fgets` if false |

---

## Non-interactive mode

When hsh is started with a script file or with stdin redirected from a
pipe, readline is bypassed entirely:

```c
if (isatty(STDIN_FILENO)) {
    line = readline(prompt);
} else {
    line = fgets_line(stdin);   /* simple fgets wrapper */
}
```

This avoids readline's raw-mode setup and prompt output cluttering
script output.
