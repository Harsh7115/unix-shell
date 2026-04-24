# Shell Grammar Reference

This document describes the grammar understood by the unix-shell parser.
The notation follows POSIX BNF conventions (lowercase = non-terminal,
UPPERCASE = terminal token).

---

## Top-Level Structure

```
program         : list EOF
                | EOF
                ;

list            : list NEWLINE pipeline
                | list SEMI   pipeline
                | list AMP    pipeline
                | pipeline
                ;

pipeline        : pipeline PIPE command
                | command
                ;

command         : simple_command
                | compound_command
                | compound_command redirect_list
                ;
```

---

## Simple Commands

```
simple_command  : cmd_prefix cmd_word cmd_suffix
                | cmd_prefix cmd_word
                | cmd_prefix
                | cmd_name cmd_suffix
                | cmd_name
                ;

cmd_name        : WORD
                ;

cmd_word        : WORD
                ;

cmd_prefix      : io_redirect
                | cmd_prefix io_redirect
                | ASSIGNMENT_WORD
                | cmd_prefix ASSIGNMENT_WORD
                ;

cmd_suffix      : io_redirect
                | cmd_suffix io_redirect
                | WORD
                | cmd_suffix WORD
                ;
```

**Examples:**
```sh
ls -la /tmp                   # cmd_name + cmd_suffix (two WORDs)
FOO=bar ls                    # cmd_prefix (assignment) + cmd_name
FOO=bar > out.txt             # cmd_prefix + io_redirect only
```

---

## Compound Commands

```
compound_command : brace_group
                 | subshell
                 | for_clause
                 | if_clause
                 | while_clause
                 | until_clause
                 ;

brace_group      : LBRACE list RBRACE
                 ;

subshell         : LPAREN list RPAREN
                 ;
```

---

## Control Structures

### if / elif / else

```
if_clause  : IF compound_list THEN compound_list else_part FI
           | IF compound_list THEN compound_list           FI
           ;

else_part  : ELIF compound_list THEN compound_list else_part
           | ELIF compound_list THEN compound_list
           | ELSE compound_list
           ;
```

### for

```
for_clause : FOR name                              do_group
           | FOR name NEWLINE+                     do_group
           | FOR name IN          NEWLINE+ do_group
           | FOR name IN wordlist NEWLINE+ do_group
           ;

wordlist   : wordlist WORD
           | WORD
           ;

do_group   : DO compound_list DONE
           ;
```

### while / until

```
while_clause : WHILE compound_list do_group ;
until_clause : UNTIL compound_list do_group ;
```

---

## Redirections

```
redirect_list  : io_redirect
               | redirect_list io_redirect
               ;

io_redirect    : io_file
               | IO_NUMBER io_file
               | io_here
               | IO_NUMBER io_here
               ;

io_file        : LESS      filename   /* input  < file  */
               | LESSAND   filename   /* dup    <& fd   */
               | GREAT     filename   /* output > file  */
               | DGREAT    filename   /* append >> file */
               | GREATAND  filename   /* dup    >& fd   */
               | LESSGREAT filename   /* rdwr  <> file  */
               | CLOBBER   filename   /* force >| file  */
               ;

io_here        : DLESS     here_end   /* here-doc  << END */
               | DLESSDASH here_end   /* strip tabs <<- END */
               ;

filename       : WORD ;
here_end       : WORD ;
```

---

## Tokens

| Token | Meaning |
|-------|---------|
| `WORD` | Any unquoted, single-quoted, double-quoted, or `$(...)`-expanded word |
| `ASSIGNMENT_WORD` | `NAME=VALUE` at command start |
| `IO_NUMBER` | A digit immediately before `<` or `>` |
| `NEWLINE` | Literal newline (statement separator) |
| `SEMI` | `;` (sequential execution) |
| `AMP` | `&` (background execution) |
| `PIPE` | `|` (pipeline) |
| `LBRACE` / `RBRACE` | `{` / `}` (brace group) |
| `LPAREN` / `RPAREN` | `(` / `)` (subshell) |

---

## Operator Precedence (highest → lowest)

1. Grouping: `{ }` / `( )`
2. Pipeline: `|`
3. Sequential: `;` / `&`
4. List separator: newline

---

## Word Expansion Order

The shell performs word expansions in this order (POSIX §2.6):

1. Tilde expansion (`~user`)
2. Parameter expansion (`$VAR`, `${VAR:-default}`, …)
3. Command substitution (`$(cmd)` or ``cmd``)
4. Arithmetic expansion (`$((expr))`)
5. Field splitting (on `$IFS`)
6. Pathname expansion (globbing: `*`, `?`, `[…]`)
7. Quote removal

Expansions inside double quotes suppress steps 1, 5, and 6 but allow 2–4.
