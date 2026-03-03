#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "shell.h"

/*
 * parser.c - build a command_t AST from a token list.
 *
 * Grammar (simplified):
 *   pipeline  := simple_cmd (PIPE simple_cmd)*  [BG]
 *   simple_cmd := WORD+ redir*
 *   redir      := REDIR_IN WORD | REDIR_OUT WORD | REDIR_APPEND WORD
 *               | REDIR_STDERR WORD | REDIR_STDERR_STDOUT
 */

static simple_cmd_t *simple_cmd_new(void) {
    simple_cmd_t *sc = calloc(1, sizeof(*sc));
    sc->argv = malloc(8 * sizeof(char *));
    sc->argc = 0;
    sc->argv_cap = 8;
    return sc;
}

static void simple_cmd_push_arg(simple_cmd_t *sc, const char *word) {
    if (sc->argc + 1 >= sc->argv_cap) {
        sc->argv_cap *= 2;
        sc->argv = realloc(sc->argv, sc->argv_cap * sizeof(char *));
    }
    sc->argv[sc->argc++] = strdup(word);
    sc->argv[sc->argc] = NULL;   /* always NULL-terminate */
}

static int is_redir(token_type_t t) {
    return t == TOK_REDIR_IN || t == TOK_REDIR_OUT ||
           t == TOK_REDIR_APPEND || t == TOK_REDIR_STDERR ||
           t == TOK_REDIR_STDERR_STDOUT;
}

/* parse one simple command; return NULL on empty input */
static simple_cmd_t *parse_simple(token_list_t *tl, int *pos) {
    simple_cmd_t *sc = simple_cmd_new();

    while (*pos < tl->count) {
        token_t *tok = &tl->tokens[*pos];

        if (tok->type == TOK_EOF || tok->type == TOK_PIPE ||
            tok->type == TOK_BG)
            break;

        if (tok->type == TOK_WORD) {
            simple_cmd_push_arg(sc, tok->value);
            (*pos)++;
        } else if (tok->type == TOK_REDIR_STDERR_STDOUT) {
            sc->stderr_to_stdout = 1;
            (*pos)++;
        } else if (is_redir(tok->type)) {
            token_type_t rtype = tok->type;
            (*pos)++;
            if (*pos >= tl->count || tl->tokens[*pos].type != TOK_WORD) {
                fprintf(stderr, "hsh: syntax error near redirection
");
                /* skip */
                continue;
            }
            char *target = tl->tokens[*pos].value;
            (*pos)++;

            switch (rtype) {
            case TOK_REDIR_IN:
                free(sc->redir_in);
                sc->redir_in = strdup(target);
                break;
            case TOK_REDIR_OUT:
                free(sc->redir_out);
                sc->redir_out = strdup(target);
                sc->redir_append = 0;
                break;
            case TOK_REDIR_APPEND:
                free(sc->redir_out);
                sc->redir_out = strdup(target);
                sc->redir_append = 1;
                break;
            case TOK_REDIR_STDERR:
                free(sc->redir_err);
                sc->redir_err = strdup(target);
                break;
            default:
                break;
            }
        } else {
            (*pos)++;   /* unexpected, skip */
        }
    }

    if (sc->argc == 0 && !sc->redir_in && !sc->redir_out) {
        free_simple_cmd(sc);
        return NULL;
    }
    return sc;
}

command_t *parse_line(const char *line) {
    token_list_t *tl = lex(line);
    if (!tl) return NULL;

    command_t *cmd = calloc(1, sizeof(*cmd));
    cmd->cmds = malloc(8 * sizeof(simple_cmd_t *));
    cmd->ncmds = 0;
    cmd->cap = 8;

    int pos = 0;
    while (pos < tl->count && tl->tokens[pos].type != TOK_EOF) {
        simple_cmd_t *sc = parse_simple(tl, &pos);
        if (sc) {
            if (cmd->ncmds >= cmd->cap) {
                cmd->cap *= 2;
                cmd->cmds = realloc(cmd->cmds, cmd->cap * sizeof(simple_cmd_t *));
            }
            cmd->cmds[cmd->ncmds++] = sc;
        }

        if (pos < tl->count && tl->tokens[pos].type == TOK_PIPE)
            pos++;
        else if (pos < tl->count && tl->tokens[pos].type == TOK_BG) {
            cmd->background = 1;
            pos++;
        }
    }

    free_token_list(tl);

    if (cmd->ncmds == 0) {
        free_command(cmd);
        return NULL;
    }
    return cmd;
}

void free_simple_cmd(simple_cmd_t *sc) {
    if (!sc) return;
    for (int i = 0; i < sc->argc; i++) free(sc->argv[i]);
    free(sc->argv);
    free(sc->redir_in);
    free(sc->redir_out);
    free(sc->redir_err);
    free(sc);
}

void free_command(command_t *cmd) {
    if (!cmd) return;
    for (int i = 0; i < cmd->ncmds; i++) free_simple_cmd(cmd->cmds[i]);
    free(cmd->cmds);
    free(cmd);
}
