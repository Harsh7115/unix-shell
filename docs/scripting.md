# Scripting Guide

This guide covers using unix-shell (`msh`) as a script interpreter.

---

## 1. Shebang Line

```sh
#!/usr/bin/env msh
echo "Hello from msh"
```

Run a script explicitly:

```bash
msh script.sh
msh -c 'echo "inline command"'
```

---

## 2. Variables

```sh
name="Alice"
count=0
echo "Hello, $name"
echo "Count: ${count}"
echo "${HOME:-/tmp}"   # default value
echo "${#name}"        # string length => 5
```

---

## 3. Arithmetic Expansion

```sh
x=10
y=$((x * 3 + 2))   # => 32
i=0; i=$((i + 1))  # increment
[ $((x % 2)) -eq 0 ] && echo "even" || echo "odd"
```

Supported operators: `+ - * / % << >> & | ^ ~ ! && || ?: =` and compound
assignment (`+= -= *= /=`).

---

## 4. Control Flow

### if / elif / else

```sh
if [ "$1" = "hello" ]; then
    echo "greeting"
elif [ "$1" = "bye" ]; then
    echo "farewell"
else
    echo "unknown: $1"
fi
```

### while / for

```sh
i=1
while [ $i -le 5 ]; do
    echo "iteration $i"
    i=$((i + 1))
done

for fruit in apple banana cherry; do
    echo "$fruit"
done

for f in *.c; do
    gcc -c "$f"
done
```

### case

```sh
case "$1" in
    start) echo "starting" ;;
    stop)  echo "stopping" ;;
    re*)   echo "restarting" ;;
    *)     echo "unknown: $1" ;;
esac
```

---

## 5. Functions

```sh
greet() {
    local name="$1"
    echo "Hello, ${name:-world}!"
    return 0
}
greet "Alice"
```

`local` limits variable scope. `return N` sets `$?`.

---

## 6. Pipelines and Redirection

```sh
ls -1 | sort | uniq -c | sort -rn | head -10
echo "log" >> /tmp/app.log
gcc foo.c 2>/tmp/errors.log
make 2>&1 | tee build.log

cat <<EOF
Line one
Line two
EOF
```

---

## 7. Exit Codes and Error Handling

```sh
#!/usr/bin/env msh
set -e          # exit on any error
set -u          # treat unset variables as errors
set -o pipefail # pipeline fails if any stage fails
```

`$?` holds the last command exit code. Convention:
0 = success, 1-125 = error, 126 = not executable, 127 = not found.

---

## 8. Positional Parameters

| Variable | Meaning |
|----------|---------|
| `$0` | Script name |
| `$1`-`$9` | Positional parameters |
| `$#` | Number of parameters |
| `$@` | All parameters as separate words |
| `$*` | All parameters joined |
| `$$` | PID of current shell |
| `$!` | PID of last background job |
| `$?` | Exit status of last command |

---

## 9. Known Limitations vs. POSIX sh

| Feature | Status |
|---------|--------|
| Arithmetic expansion `$(( ))` | Supported |
| Command substitution `$( )` | Supported |
| Here-documents `<<EOF` | Supported |
| Process substitution `<( )` | Partial |
| Arrays | Not supported |
| `select` construct | Not supported |
| `getopts` | Supported |
| Brace expansion `{a,b}` | Not supported |

See [features.md](features.md) for the full matrix.

---

## 10. Debugging Scripts

```sh
set -x    # print each command before executing
set +x    # disable trace
```

`-x` prefixes each expanded command with `+` so you can see exactly what
the shell executes.  Redirect stderr to a file to separate trace from output.

---

## See Also

- [builtins.md](builtins.md)
- [grammar.md](grammar.md)
- [exit-codes.md](exit-codes.md)
- [job-control.md](job-control.md)
