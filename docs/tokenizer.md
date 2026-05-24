# Tokenizer & Lexer Internals

The tokenizer is the first stage of the shell's input pipeline.  It converts
a raw character stream into a flat list of **tokens** that the parser then
assembles into a command tree.

---

## Token Types

| Token type | Examples | Notes |
|------------|----------|-------|
| `WORD`      | `ls`, `foo`, `"bar baz"`, `'qux'` | Any non-operator sequence |
| `ASSIGN`    | `FOO=bar` | Only at start of a simple command |
| `PIPE`      | `|` | Pipeline separator |
| `REDIR_IN`  | `<` | Redirect stdin |
| `REDIR_OUT` | `>` | Redirect stdout (truncate) |
| `REDIR_APP` | `>>` | Redirect stdout (append) |
| `REDIR_ERR` | `2>` | Redirect stderr |
| `REDIR_BOTH`| `&>` | Redirect stdout + stderr |
| `BACKGROUND`| `&` | Run pipeline in background |
| `SEMICOLON` | `;` | Sequential command separator |
| `NEWLINE`   | `\n` | Treated like `;` in most contexts |
| `EOF`       | — | End of input |

---

## Tokenizer State Machine

The tokenizer is implemented as a hand-written finite automaton in
`src/tokenizer.c`.  It operates character-by-character over the input
buffer and maintains one of the following states:

```
START          initial / between tokens
IN_WORD        accumulating an unquoted word
IN_SQ          inside single quotes  (' ... ')
IN_DQ          inside double quotes  (" ... ")
IN_ESC_DQ      saw backslash inside double quotes
IN_ESC_BARE    saw backslash outside quotes
IN_COMMENT     saw '#'; discard until newline
```

### State transitions (simplified)

```
START
  whitespace        → START           (skip)
  '#'               → IN_COMMENT
  '\'              → IN_ESC_BARE
  '\''             → IN_SQ           (start single-quoted word)
  '"'               → IN_DQ           (start double-quoted word)
  '|', '<', '>', ';'→ emit operator token, stay in START
  '&'               → peek next char:
                       '&'  → emit AND_IF, advance
                       '>'  → emit REDIR_BOTH, advance
                       else → emit BACKGROUND
  other             → IN_WORD, accumulate

IN_WORD
  whitespace        → emit WORD, → START
  operator          → emit WORD, emit operator, → START
  '\'              → IN_ESC_BARE
  '\''             → IN_SQ          (quoting mid-word is allowed)
  '"'               → IN_DQ
  other             → accumulate

IN_SQ
  '\''             → back to previous state (IN_WORD or START→WORD)
  EOF               → syntax error: unclosed single quote
  other             → accumulate verbatim (no escaping inside '')

IN_DQ
  '"'               → back to previous state
  '\'              → IN_ESC_DQ
  '$', '`'         → begin expansion (handled in expander, not tokenizer)
  EOF               → syntax error: unclosed double quote
  other             → accumulate

IN_ESC_DQ
  '\n'             → discard both (line continuation)
  '$','\\','"','\'' → accumulate the literal character, → IN_DQ
  other             → accumulate '\\' + char literally, → IN_DQ

IN_ESC_BARE
  '\n'             → discard both (line continuation), → START
  other             → accumulate char literally, → IN_WORD
```

---

## Quoting Rules

The shell implements the three POSIX quoting mechanisms:

### 1. Backslash (`\\`)

Outside quotes, a backslash preserves the literal value of the next character
and suppresses any special meaning it would otherwise have.

```sh
echo \$HOME   # prints: $HOME  (not expanded)
echo a\ b     # prints: a b    (space not a delimiter)
```

Inside double quotes, backslash is only an escape character before:
`$`, ``\```, `"`, `\\`, and `\n` (newline continuation).

### 2. Single quotes (`'...'`)

Everything between single quotes is taken literally — no expansions, no
escape processing.  A single quote cannot appear inside single quotes, even
preceded by a backslash.

```sh
echo '$HOME'   # prints: $HOME
echo '\n'     # prints: \n  (two characters, not a newline)
```

### 3. Double quotes (`"..."`)

Inside double quotes, parameter expansion (`$VAR`), command substitution
(`$(cmd)`), and arithmetic expansion (`$((...))`) are still performed.
All other characters are taken literally.

```sh
NAME=world
echo "hello $NAME"   # prints: hello world
echo "a  b"           # prints: a  b  (spaces preserved as-is)
```

---

## Word Splitting

After expansion, unquoted results undergo **word splitting** on the
characters in `$IFS` (default: space, tab, newline).  Quoted expansions
are never split.

```sh
FILES="a.c b.c c.c"
gcc $FILES          # splits into: gcc a.c b.c c.c
gcc "$FILES"        # no split:    gcc "a.c b.c c.c"  (one argument)
```

The tokenizer marks each WORD token with a `quoted` flag so the expander
can suppress word splitting for fully-quoted tokens.

---

## Operator Disambiguation

Several operator characters are ambiguous without lookahead:

| Input | Tokenises as |
|-------|-------------|
| `>`  | `REDIR_OUT` |
| `>>` | `REDIR_APP` (one extra `>`) |
| `&`  | `BACKGROUND` |
| `&>` | `REDIR_BOTH` |
| `2>` | `REDIR_ERR` (digit immediately before `>`) |

The tokenizer uses a single character of lookahead for `>`/`>>` and
`&`/`&>`.  The `2>` case is handled by checking whether the immediately
preceding token (still in the accumulation buffer) is the digit `2` with
nothing else in the word.

---

## Error Handling

The tokenizer sets a global `tok_error` flag and an error message on:

- Unclosed single or double quote at EOF
- Illegal byte sequence (non-UTF-8 in a locale that requires UTF-8)

The parser checks `tok_error` after each call to `next_token()` and prints
a `syntax error` message to stderr before returning a non-zero exit code.

---

## API

```c
/* src/tokenizer.h */

typedef enum {
    TOK_WORD, TOK_ASSIGN, TOK_PIPE, TOK_SEMICOLON,
    TOK_REDIR_IN, TOK_REDIR_OUT, TOK_REDIR_APP,
    TOK_REDIR_ERR, TOK_REDIR_BOTH,
    TOK_BACKGROUND, TOK_NEWLINE, TOK_EOF,
    TOK_ERROR
} TokenType;

typedef struct {
    TokenType  type;
    char      *value;   /* heap-allocated; caller must free */
    int        quoted;  /* 1 if any part was inside quotes */
    int        lineno;  /* source line (for error messages) */
} Token;

/* Initialise tokenizer over a NUL-terminated input string. */
void tok_init(const char *input);

/* Return the next token (caller owns token.value). */
Token tok_next(void);

/* Peek at the next token without consuming it. */
Token tok_peek(void);

/* Free memory held by a Token. */
void tok_free(Token *t);
```
