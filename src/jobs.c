#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>
#include "shell.h"

/*
 * jobs.c - simple foreground/background job table.
 *
 * We keep a flat array of up to MAX_JOBS entries.  The shell reaps
 * finished jobs lazily on every call to jobs_print() and before
 * printing a new prompt (via the SIGCHLD handler stub below).
 */

#define MAX_JOBS 64

static job_t job_table[MAX_JOBS];
static int   njobs = 0;
static int   next_jid = 1;

void jobs_init(void) {
    memset(job_table, 0, sizeof(job_table));
    njobs = 0;
    next_jid = 1;
}

void jobs_cleanup(void) {
    /* send SIGHUP to any remaining background jobs */
    for (int i = 0; i < njobs; i++) {
        if (job_table[i].state == JOB_RUNNING)
            kill(job_table[i].pid, SIGHUP);
    }
}

void job_add(pid_t pid, const char *name) {
    if (njobs >= MAX_JOBS) {
        fprintf(stderr, "hsh: job table full
");
        return;
    }
    job_t *j = &job_table[njobs++];
    j->id    = next_jid++;
    j->pid   = pid;
    j->state = JOB_RUNNING;
    strncpy(j->name, name ? name : "?", sizeof(j->name) - 1);
}

void job_remove(pid_t pid) {
    for (int i = 0; i < njobs; i++) {
        if (job_table[i].pid == pid) {
            /* compact array */
            memmove(&job_table[i], &job_table[i+1],
                    (njobs - i - 1) * sizeof(job_t));
            njobs--;
            return;
        }
    }
}

/* reap any finished jobs (non-blocking) */
static void reap_jobs(void) {
    int status;
    pid_t pid;
    while ((pid = waitpid(-1, &status, WNOHANG | WUNTRACED)) > 0) {
        for (int i = 0; i < njobs; i++) {
            if (job_table[i].pid == pid) {
                if (WIFSTOPPED(status))
                    job_table[i].state = JOB_STOPPED;
                else
                    job_table[i].state = JOB_DONE;
                break;
            }
        }
    }
}

void jobs_print(void) {
    reap_jobs();
    for (int i = 0; i < njobs; i++) {
        const char *state_str =
            job_table[i].state == JOB_RUNNING ? "Running" :
            job_table[i].state == JOB_STOPPED ? "Stopped" : "Done";
        printf("[%d] %d  %-10s  %s
",
               job_table[i].id, job_table[i].pid,
               state_str, job_table[i].name);
    }
    /* remove done jobs */
    for (int i = njobs - 1; i >= 0; i--) {
        if (job_table[i].state == JOB_DONE) {
            memmove(&job_table[i], &job_table[i+1],
                    (njobs - i - 1) * sizeof(job_t));
            njobs--;
        }
    }
}

int job_fg(int jid) {
    reap_jobs();
    for (int i = 0; i < njobs; i++) {
        if (job_table[i].id == jid || (jid == -1 && i == njobs - 1)) {
            pid_t pid = job_table[i].pid;
            job_table[i].state = JOB_RUNNING;
            /* put it back in the foreground process group */
            tcsetpgrp(STDIN_FILENO, getpgid(pid));
            kill(pid, SIGCONT);
            int status;
            waitpid(pid, &status, WUNTRACED);
            tcsetpgrp(STDIN_FILENO, getpgrp());
            if (WIFSTOPPED(status))
                job_table[i].state = JOB_STOPPED;
            else
                job_remove(pid);
            return 0;
        }
    }
    fprintf(stderr, "hsh: fg: no such job: %d
", jid);
    return 1;
}

int job_bg(int jid) {
    reap_jobs();
    for (int i = 0; i < njobs; i++) {
        if (job_table[i].id == jid || (jid == -1 && i == njobs - 1)) {
            job_table[i].state = JOB_RUNNING;
            kill(job_table[i].pid, SIGCONT);
            printf("[%d] %d continued  %s
",
                   job_table[i].id, job_table[i].pid, job_table[i].name);
            return 0;
        }
    }
    fprintf(stderr, "hsh: bg: no such job: %d
", jid);
    return 1;
}
