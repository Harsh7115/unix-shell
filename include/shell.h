#ifndef SHELL_H
#define SHELL_H

#include <sys/types.h>
#include <readline/readline.h>
#include <readline/history.h>

/* ── prompt ──────────────────────────────────────────────────── */
#define SHELL_PROMPT  "hsh> "

/* ── token types ─────────────────────────────────────────────── */
typedef enum {
    TOK_WORD,
    TOK_PIPE,               /* |  */
    TOK_REDIR_IN,           /* <  */
    TOK_REDIR_OUT,          /* >  */
    TOK_REDIR_APPEND,       /* >> */
    TOK_REDIR_STDERR,       /* 2> */
    TOK_REDIR_STDERR_STDOUT,/* 2>&1 */
    TOK_BG,                 /* &  */
    TOK_EOF,
} token_type_t;

typedef struct {
    token_type_t  type;
    char         *value;    /* heap-allocated, NULL for non-word tokens */
} token_t;

typedef struct {
    token_t *tokens;
    int      count;
    int      capacity;
} token_list_t;

/* ── AST nodes ───────────────────────────────────────────────── */
typedef struct {
    char  **argv;           /* NULL-terminated argument vector */
    int     argc;
    int     argv_cap;
    char   *redir_in;       /* filename for < */
    char   *redir_out;      /* filename for > / >> */
    char   *redir_err;      /* filename for 2> */
    int     redir_append;   /* 1 if >> */
    int     stderr_to_stdout; /* 1 if 2>&1 */
} simple_cmd_t;

typedef struct {
    simple_cmd_t **cmds;
    int            ncmds;
    int            cap;
    int            background; /* 1 if trailing & */
} command_t;

/* ── job table ───────────────────────────────────────────────── */
typedef enum { JOB_RUNNING, JOB_STOPPED, JOB_DONE } job_state_t;

typedef struct {
    int         id;
    pid_t       pid;
    job_state_t state;
    char        name[256];
} job_t;

/* ── function prototypes ─────────────────────────────────────── */

/* lexer.c */
token_list_t *lex(const char *line);
void          free_token_list(token_list_t *tl);

/* parser.c */
command_t    *parse_line(const char *line);
void          free_command(command_t *cmd);
void          free_simple_cmd(simple_cmd_t *sc);

/* executor.c */
void          execute(command_t *cmd);

/* builtins.c */
int           run_builtin(simple_cmd_t *sc);

/* jobs.c */
void          jobs_init(void);
void          jobs_cleanup(void);
void          job_add(pid_t pid, const char *name);
void          job_remove(pid_t pid);
void          jobs_print(void);
int           job_fg(int jid);
int           job_bg(int jid);

#endif /* SHELL_H */
