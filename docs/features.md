# unix-shell Feature Reference

A complete reference for all features supported by this POSIX-compliant Unix
shell.  The shell targets POSIX.1-2017 and is compatible with bash scripts
that use only standard features.

---

## 1. Command Execution

### 1.1 Simple Commands
```sh
command [arg ...]
```
The shell forks a child process, resolves `command` via `PATH`, and calls
`execvp()`.  Exit status is stored in `$?`.

### 1.2 Compound Commands

| Syntax | Behaviour |
|--------|-----------|
| `cmd1 ; cmd2` | Run cmd1 then cmd2 sequentially |
| `cmd1 && cmd2` | Run cmd2 only if cmd1 succeeds |
| `cmd1 \|\| cmd2` | Run cmd2 only if cmd1 fails |
| `(cmd)` | Run cmd in a subshell |

---

## 2. Pipelines

```sh
cmd1 | cmd2 | cmd3
```
Each command runs in its own forked process. stdout of each is connected to
stdin of the next via an `O_CLOEXEC` pipe. The pipeline exit status is the
exit status of the **last** command.

---

## 3. Redirection

| Operator | Meaning |
|----------|---------|
| `> file` | Redirect stdout to file (truncate) |
| `>> file` | Redirect stdout to file (append) |
| `< file` | Redirect stdin from file |
| `2> file` | Redirect stderr to file |
| `2>&1` | Redirect stderr to current stdout |
| `&> file` | Redirect both stdout and stderr |
| `<< DELIM` | Here-document |
| `<<- DELIM` | Here-document, strip leading tabs |

---

## 4. Job Control

Full POSIX job control when attached to a terminal:

- **Foreground job** — runs with terminal process group; Ctrl-C sends SIGINT, Ctrl-Z sends SIGTSTP.
- **Background job** — launched with trailing `&`; runs in a new process group.
- **`fg [%job]`** — bring background/stopped job to foreground.
- **`bg [%job]`** — resume stopped job in the background.
- **`jobs [-l]`** — list active jobs with optional PIDs.

Job references: `%1`, `%2`, `%%` (current), `%-` (previous).

---

## 5. Built-in Commands

| Command | Description |
|---------|-------------|
| `cd [dir]` | Change directory; `cd -` returns to previous |
| `exit [n]` | Exit with optional status |
| `export VAR[=val]` | Mark variable for export |
| `unset VAR` | Remove variable or function |
| `set [-/+efnux]` | Set/unset shell options |
| `shift [n]` | Shift positional parameters |
| `source / .` | Execute file in current shell context |
| `exec cmd` | Replace shell process with cmd |
| `echo [-n] [-e]` | Print to stdout |
| `printf fmt [args]` | Formatted output |
| `read [-r] VAR` | Read line from stdin |
| `wait [pid]` | Wait for background processes |
| `kill [-sig] pid` | Send signal to process |
| `pwd` | Print working directory |
| `alias / unalias` | Define/remove aliases |
| `history` | Show command history |
| `type cmd` | Describe how cmd would be interpreted |

---

## 6. Variables and Expansion

### 6.1 Parameter Expansion

| Form | Meaning |
|------|---------|
| `${VAR}` | Value of VAR |
| `${VAR:-default}` | Value, or default if unset/empty |
| `${VAR:=default}` | Assign default if unset, then expand |
| `${VAR:?msg}` | Error with msg if unset |
| `${#VAR}` | Length of VAR |
| `${VAR#pattern}` | Remove shortest prefix match |
| `${VAR##pattern}` | Remove longest prefix match |
| `${VAR%pattern}` | Remove shortest suffix match |
| `${VAR/pat/rep}` | Replace first match |

### 6.2 Special Variables

| Variable | Value |
|----------|-------|
| `$0` | Shell/script name |
| `$1`-`$9` | Positional parameters |
| `$@` | All positional parameters (separate) |
| `$#` | Number of positional parameters |
| `$?` | Last exit status |
| `$$` | Current shell PID |
| `$!` | Last background PID |

---

## 7. Quoting

| Form | Effect |
|------|--------|
| `\` | Escape next character |
| `'...'` | Single quotes — no expansion |
| `"..."` | Double quotes — allow $ expansion |
| `$(...)` | Command substitution |
| `$((...)) ` | Arithmetic expansion |

---

## 8. Control Flow

```sh
if cmd; then ... elif cmd; then ... else ... fi
while cmd; do ... done
until cmd; do ... done
for var in word ...; do ... done
case word in pattern) ... ;; esac
```

---

## 9. Functions

```sh
fname() { body; }
```
- Run in current shell environment
- Support recursive calls
- `local VAR=value` for local variables
