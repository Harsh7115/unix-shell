# Pipe Implementation

A walkthrough of how `hsh` builds and executes pipeline chains like:

```
cat /etc/passwd | grep root | cut -d: -f1 | tr a-z A-Z
```

---

## 1. Parsing: Building the Command Tree

The lexer tokenises the input and recognises `|` as a `TOKEN_PIPE` separator. The parser then assembles a linked list of `Command` structs:

```c
// include/shell.h (simplified)
typedef struct Command {
    char        **argv;       // NULL-terminated argument vector
    char         *infile;     // < redirection (NULL if none)
    char         *outfile;    // > or >> redirection (NULL if none)
    int           append;     // 1 if >>, 0 if >
    struct Command *next;     // next stage in pipeline (NULL if last)
} Command;
```

A pipeline of N stages produces a linked list of N `Command` nodes. Single commands are just a one-node list.

---

## 2. Execution: Left-to-Right Pipe Construction

Pipe execution is handled in `src/executor.c: exec_pipeline()`. The algorithm walks the linked list left-to-right, creating one `pipe(2)` pair per boundary between adjacent commands:

```
Stage 0        Stage 1        Stage 2
cat            grep           cut
  stdout ──►  pipe[0] ──► stdin
                 stdout ──►  pipe[1] ──► stdin
                                 stdout ──► terminal
```

### Step-by-step

```c
void exec_pipeline(Command *head, int in_fd) {
    if (head == NULL) return;

    int pipefd[2];
    int next_in = in_fd;   // read end for the current stage

    for (Command *cmd = head; cmd != NULL; cmd = cmd->next) {
        int out_fd;

        if (cmd->next != NULL) {
            // Not the last stage: create a pipe
            if (pipe(pipefd) < 0)
                die("pipe");
            out_fd = pipefd[1];   // write end goes to this stage's stdout
        } else {
            // Last stage: inherit the shell's stdout (or redirection target)
            out_fd = STDOUT_FILENO;
        }

        pid_t pid = fork();
        if (pid == 0) {
            // ── child ──────────────────────────────────────────────────
            if (next_in != STDIN_FILENO) {
                dup2(next_in, STDIN_FILENO);
                close(next_in);
            }
            if (out_fd != STDOUT_FILENO) {
                dup2(out_fd, STDOUT_FILENO);
                close(out_fd);
            }
            // Close the read end of the new pipe in the child writing to it
            if (cmd->next != NULL)
                close(pipefd[0]);

            apply_redirections(cmd);   // handle <, >, >> on this stage
            execvp(cmd->argv[0], cmd->argv);
            perror(cmd->argv[0]);
            _exit(127);
        }

        // ── parent ──────────────────────────────────────────────────────
        // Close the write end (child now owns it via dup2)
        if (out_fd != STDOUT_FILENO)
            close(out_fd);
        // The read end of the new pipe becomes stdin for the next stage
        if (cmd->next != NULL) {
            if (next_in != STDIN_FILENO)
                close(next_in);    // done with previous read end
            next_in = pipefd[0];
        }
    }

    // Wait for all children in the pipeline
    wait_pipeline(head);
}
```

### Why close early?

Every unused file descriptor copy of a pipe's write end **must be closed** in the parent (and in children that don't write to it). Otherwise the reading stage never sees EOF — its `read(2)` blocks forever because the kernel counts open write-end references.

---

## 3. Process Groups and Job Control

Every pipeline is executed in its own **process group** so that Ctrl-C only kills the foreground pipeline, not the shell itself:

```c
// In the child, immediately after fork():
setpgid(0, 0);   // create new process group; PGID = child's PID

// In the parent (for interactive shells), also set the group
// to avoid a race where the child runs before the parent calls tcsetpgrp:
setpgid(pid, pipeline_pgid);
```

The first child's PID becomes the **pipeline PGID**. Subsequent children in the same pipeline join that group:

```c
setpgid(0, pipeline_pgid);
```

Once all children are forked, the shell gives the process group the terminal:

```c
tcsetpgrp(STDIN_FILENO, pipeline_pgid);
```

After the pipeline finishes, the shell reclaims the terminal:

```c
tcsetpgrp(STDIN_FILENO, getpgrp());
```

---

## 4. Exit Code Semantics

POSIX specifies that a pipeline's exit status is the exit status of the **last (rightmost) command**. `hsh` waits for all children via `waitpid` and records the exit status of the final stage only:

```c
// pseudo-code in wait_pipeline()
int last_status = 0;
for each child PID in pipeline order:
    waitpid(pid, &status, 0);
    if this is the last stage:
        last_status = WEXITSTATUS(status);
$? = last_status;
```

---

## 5. Mixing Pipes and Redirections

Redirections on individual pipeline stages are applied **after** `dup2` of the pipe ends, so a stage can both read from the previous pipe and redirect its output:

```bash
cat /dev/stdin | grep foo > matches.txt
#               ^^^^^^^^^^^^^^^^^
#  grep reads from pipe, writes to file — both work simultaneously
```

The order of `dup2` calls in the child is:

1. `dup2(pipe_read_end, STDIN_FILENO)`  — connect pipeline input
2. `dup2(pipe_write_end, STDOUT_FILENO)` — connect pipeline output
3. Apply `<` / `>` / `>>` redirections from the `Command` struct (these overwrite fds 0/1 again if present)

This means an explicit `>` on a non-final stage will redirect that stage's output to a file instead of the next pipe. Handy for `tee`-like patterns; surprising if unintentional.

---

## 6. Built-ins in Pipelines

POSIX allows built-ins to appear anywhere in a pipeline. In `hsh`:

- **Non-final stage**: the built-in runs in a **child process** (forked normally) so its stdout feeds the next pipe stage. Side-effects (e.g. `cd`) are lost.
- **Final stage**: if the pipeline is a single built-in, it runs in the shell process itself (no fork). If it is the final stage of a multi-stage pipeline, it is currently forked (same as non-final). Future work: `exec` the final built-in in the shell process.

---

## 7. Error Handling

| Error condition | Behaviour |
|----------------|-----------|
| `pipe(2)` fails | `perror` + abort pipeline, set `$? = 1` |
| `fork(2)` fails | `perror` + abort remaining stages |
| `execvp` fails (command not found) | child exits 127; pipeline exit code = 127 |
| Write to broken pipe (`SIGPIPE`) | default action: child exits with signal; pipeline exit code reflects that |

`SIGPIPE` is left at its default disposition in child processes so that a broken pipe terminates the writing stage cleanly (e.g. `cat bigfile | head -1` doesn't spin forever).
