# I/O Redirection

This document covers how the shell implements POSIX-style I/O
redirection: `<`, `>`, `>>`, `2>`, `2>&1`, and here-docs (`<<`).
The goal is to be precise about *when* the redirection happens
relative to fork/exec, because that ordering is the most common
source of subtle bugs.

## 1. The mental model

Every redirection in a command line is, at runtime, a pair:

```
(target_fd, source) where source is one of:
    OPEN(path, flags, mode)
    DUP(other_fd)
    HEREDOC(byte_buffer)
```

The parser produces a vector of these pairs in **textual order**. The
executor then applies them, in that order, in the child process after
`fork()` and before `execvp()`. The parent's fds are never touched.

Why textual order matters:

```sh
cmd > out 2>&1     # 2>&1 sees out, so stderr -> out
cmd 2>&1 > out     # 2>&1 sees old stdout (terminal), then > out reopens 1
```

Both are valid POSIX; the second is the classic interview question.
Honour the order the user typed.

## 2. The dup2 dance

For each `(target_fd, source)`:

1. **Resolve source to a file descriptor.**
   * `OPEN`: `open(path, flags, 0644)` — `flags` differs by operator
     (`O_RDONLY` for `<`, `O_WRONLY|O_CREAT|O_TRUNC` for `>`,
     `O_WRONLY|O_CREAT|O_APPEND` for `>>`).
   * `DUP`: just take the integer.
   * `HEREDOC`: write the buffer to the read end of a pipe and use
     the read end (see §4).
2. **`dup2(source_fd, target_fd)`.** This atomically closes
   `target_fd` if open, then makes `target_fd` an alias for
   `source_fd`.
3. **Close `source_fd` if it was opened transiently** (i.e. came
   from `OPEN` or `HEREDOC`, not `DUP`).

Common mistakes the implementation guards against:

* Forgetting step 3, leaking fds into `exec`.
* Calling `close(target_fd)` before `dup2`. Use the atomic form;
  there is no race window where `target_fd` is invalid.
* Using `dup` instead of `dup2`. `dup` picks the lowest free fd,
  which is rarely what you want.

## 3. Save-and-restore for builtins

Built-ins like `cd`, `exit`, `export` run **in the parent process**
— they have to, to mutate shell state. If the user types

```sh
cd /tmp > log.txt
```

we cannot just apply the redirection in the parent, because that
would also redirect the next prompt. The shell instead does:

```c
int saved[3] = { dup(0), dup(1), dup(2) };
apply_redirections(redir_list);
int rc = run_builtin(argv);
restore_fds(saved);
```

`restore_fds` is itself a sequence of `dup2` + `close` calls. The
saved descriptors are marked `FD_CLOEXEC` so that if any builtin
invokes `exec` (`exec >> log.txt`, etc.) the saved copies are not
inherited.

## 4. Here-docs

`<< EOF` ... `EOF` collects lines until the delimiter, performs the
appropriate expansions (none if the delimiter was quoted), and feeds
the result to the command's stdin. The implementation:

```c
int pipefd[2];
pipe(pipefd);
write(pipefd[1], heredoc_bytes, heredoc_len);
close(pipefd[1]);
dup2(pipefd[0], 0);
close(pipefd[0]);
```

For payloads larger than `PIPE_BUF` (4096 on Linux) we cannot rely on
a non-blocking write to drain into the pipe, so the implementation
forks a small writer child for big here-docs and only uses the pipe
trick for small ones. This is why the test suite has a 64 KB
here-doc test specifically.

`<<-` (tab-stripped) and `<<<` (here-string) are layered on top of
the same machinery: the only difference is how the byte buffer is
prepared.

## 5. Pipelines

A pipeline `a | b | c` sets up the pipes *before* applying any of
the per-command redirections. Sequence inside each child:

1. Replace stdin/stdout with the appropriate pipe ends.
2. Close all unused pipe ends.
3. Apply this command's explicit redirection list (which can override
   the pipe-installed fds).
4. `execvp`.

The "explicit overrides pipe" rule is observable:

```sh
echo hi | cat > out.txt   # cat's stdout goes to file, not next pipe
echo hi > out.txt | cat   # echo's stdout goes to file; cat sees EOF
```

## 6. Error semantics

If a redirection fails (`open` returns `-1`):

* For an external command: the child prints a diagnostic and exits
  with status 1; `execvp` is never called.
* For a builtin: the parent's saved fds are restored, no builtin
  is run, and `$?` is set to 1.
* The rest of the command line is **not** discarded — the next
  pipeline / list element runs as usual. This matches bash; some
  shells treat redirection failures as fatal, but POSIX permits both.
