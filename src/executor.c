#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <errno.h>
#include "shell.h"

/*
 * executor.c - fork/exec pipelines, set up redirections, manage job table.
 */

/* apply redirections for a simple_cmd in child process */
static void apply_redirections(simple_cmd_t *sc) {
    if (sc->redir_in) {
        int fd = open(sc->redir_in, O_RDONLY);
        if (fd < 0) { perror(sc->redir_in); exit(1); }
        dup2(fd, STDIN_FILENO);
        close(fd);
    }
    if (sc->redir_out) {
        int flags = O_WRONLY | O_CREAT | (sc->redir_append ? O_APPEND : O_TRUNC);
        int fd = open(sc->redir_out, flags, 0644);
        if (fd < 0) { perror(sc->redir_out); exit(1); }
        dup2(fd, STDOUT_FILENO);
        close(fd);
    }
    if (sc->redir_err) {
        int fd = open(sc->redir_err, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) { perror(sc->redir_err); exit(1); }
        dup2(fd, STDERR_FILENO);
        close(fd);
    }
    if (sc->stderr_to_stdout)
        dup2(STDOUT_FILENO, STDERR_FILENO);
}

/* find a binary via PATH; returns heap-allocated path or NULL */
static char *find_in_path(const char *cmd) {
    if (strchr(cmd, '/')) return strdup(cmd);

    char *path_env = getenv("PATH");
    if (!path_env) return NULL;

    char *path_copy = strdup(path_env);
    char *dir = strtok(path_copy, ":");
    static char buf[4096];

    while (dir) {
        snprintf(buf, sizeof(buf), "%s/%s", dir, cmd);
        if (access(buf, X_OK) == 0) {
            free(path_copy);
            return strdup(buf);
        }
        dir = strtok(NULL, ":");
    }
    free(path_copy);
    return NULL;
}

/* execute a single simple command (no pipes) */
static pid_t exec_simple(simple_cmd_t *sc, int in_fd, int out_fd, int bg) {
    /* check builtins first (only for foreground non-piped commands) */
    if (in_fd == STDIN_FILENO && out_fd == STDOUT_FILENO && !bg) {
        int handled = run_builtin(sc);
        if (handled >= 0) return 0;
    }

    pid_t pid = fork();
    if (pid < 0) { perror("fork"); return -1; }

    if (pid == 0) {
        /* child */
        if (in_fd != STDIN_FILENO)  { dup2(in_fd, STDIN_FILENO);  close(in_fd); }
        if (out_fd != STDOUT_FILENO){ dup2(out_fd, STDOUT_FILENO); close(out_fd); }
        apply_redirections(sc);

        /* restore default signal handlers for child */
        signal(SIGINT,  SIG_DFL);
        signal(SIGQUIT, SIG_DFL);
        signal(SIGTSTP, SIG_DFL);

        char *bin = find_in_path(sc->argv[0]);
        if (!bin) {
            fprintf(stderr, "hsh: %s: command not found
", sc->argv[0]);
            exit(127);
        }
        execv(bin, sc->argv);
        perror(sc->argv[0]);
        exit(1);
    }

    return pid;
}

void execute(command_t *cmd) {
    if (!cmd || cmd->ncmds == 0) return;

    /* single command, no pipes */
    if (cmd->ncmds == 1) {
        /* try builtin first */
        if (!cmd->background && run_builtin(cmd->cmds[0]) >= 0) return;

        pid_t pid = exec_simple(cmd->cmds[0], STDIN_FILENO, STDOUT_FILENO, cmd->background);
        if (pid <= 0) return;

        if (cmd->background) {
            job_add(pid, cmd->cmds[0]->argv[0]);
            printf("[bg] pid %d
", pid);
        } else {
            int status;
            waitpid(pid, &status, WUNTRACED);
            if (WIFSTOPPED(status)) {
                job_add(pid, cmd->cmds[0]->argv[0]);
                printf("
[stopped] pid %d
", pid);
            }
        }
        return;
    }

    /* pipeline */
    int n = cmd->ncmds;
    int (*pipes)[2] = malloc((n - 1) * sizeof(*pipes));
    pid_t *pids = malloc(n * sizeof(pid_t));

    for (int i = 0; i < n - 1; i++) {
        if (pipe(pipes[i]) < 0) { perror("pipe"); goto cleanup; }
    }

    for (int i = 0; i < n; i++) {
        int in_fd  = (i == 0)     ? STDIN_FILENO  : pipes[i-1][0];
        int out_fd = (i == n - 1) ? STDOUT_FILENO : pipes[i][1];
        pids[i] = exec_simple(cmd->cmds[i], in_fd, out_fd, cmd->background);
    }

    /* close all pipe ends in parent */
    for (int i = 0; i < n - 1; i++) {
        close(pipes[i][0]);
        close(pipes[i][1]);
    }

    if (!cmd->background) {
        for (int i = 0; i < n; i++) {
            if (pids[i] > 0) {
                int status;
                waitpid(pids[i], &status, WUNTRACED);
            }
        }
    } else {
        for (int i = 0; i < n; i++)
            if (pids[i] > 0)
                job_add(pids[i], cmd->cmds[i]->argv[0]);
        printf("[bg pipeline] %d procs
", n);
    }

cleanup:
    free(pipes);
    free(pids);
}
