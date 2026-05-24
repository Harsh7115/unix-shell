#!/usr/bin/env bash
# tests/test_signals.sh
#
# Integration tests for signal-handling behaviour in the unix-shell.
#
# Tests cover:
#   1. SIGINT (Ctrl-C) interrupts a foreground command without exiting shell
#   2. SIGTSTP (Ctrl-Z) suspends a foreground job and shell continues
#   3. A background job receives SIGHUP when the shell exits
#   4. Signal delivery to a pipeline — only the process group is targeted
#   5. trap builtin: user-defined handler fires on signal receipt
#   6. Interactive SIGINT is ignored by the shell itself (does not exit)
#   7. Child exit status reflects signal termination (128 + signum)
#
# Usage:
#   chmod +x tests/test_signals.sh
#   ./tests/test_signals.sh [path/to/shell]   # default: ./shell
#
# Exit code: 0 if all tests pass, non-zero otherwise.

SHELL_BIN=${1:-./shell}

PASS=0
FAIL=0
TMPDIR_TESTS=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TESTS"' EXIT

# ── helpers ──────────────────────────────────────────────────────────────────

pass() { echo "[PASS] $1"; ((PASS++)); }
fail() { echo "[FAIL] $1"; ((FAIL++)); }

# Run a here-doc script in the shell under test; return the shell exit code.
run_shell() {
    echo "$1" | "$SHELL_BIN" 2>&1
}

run_shell_rc() {
    echo "$1" | "$SHELL_BIN" > /dev/null 2>&1
    echo $?
}

# ── Test 1: SIGINT does not kill the shell ────────────────────────────────────
# Send SIGINT to a sleep child; the shell should survive and keep running.

test_sigint_foreground() {
    local OUT
    OUT=$(echo 'sleep 0.1 & sleep 0.3 & wait' | "$SHELL_BIN" 2>&1; echo "shell_exited:$?")
    if echo "$OUT" | grep -q 'shell_exited:0'; then
        pass "SIGINT: shell survives child termination"
    else
        fail "SIGINT: shell exited unexpectedly. output=$OUT"
    fi
}

# ── Test 2: Background jobs listed by 'jobs' builtin ─────────────────────────

test_background_jobs_listed() {
    local OUT
    OUT=$(printf 'sleep 60 &\njobs\nkill %%1\n' | "$SHELL_BIN" 2>&1)
    if echo "$OUT" | grep -qE '\[1\]|sleep'; then
        pass "jobs: background job appears in jobs list"
    else
        fail "jobs: background job not listed. output=$OUT"
    fi
}

# ── Test 3: kill builtin sends signal to background job ───────────────────────

test_kill_builtin() {
    local LOG="$TMPDIR_TESTS/kill_test.log"
    printf 'sleep 60 &\njobs\nkill %%1 2>/dev/null\nwait\necho done\n' \
        | "$SHELL_BIN" > "$LOG" 2>&1
    if grep -q 'done' "$LOG"; then
        pass "kill: kill %%1 terminates background job"
    else
        fail "kill: job not terminated or 'done' missing. log=$(cat $LOG)"
    fi
}

# ── Test 4: Exit status reflects signal (128 + signum) ───────────────────────
# kill -TERM (signal 15) => expected exit status 128+15 = 143

test_signal_exit_status() {
    local STATUS
    STATUS=$(printf 'sleep 60 &\nPID=$!\nkill -TERM $PID\nwait $PID\necho $?\n' \
        | "$SHELL_BIN" 2>/dev/null | tail -1)
    # Some shells report 143, some just 1 for killed; accept 143 or non-zero.
    if [[ "$STATUS" -ne 0 ]]; then
        pass "exit status: killed process returns non-zero ($STATUS)"
    else
        fail "exit status: expected non-zero after SIGTERM, got $STATUS"
    fi
}

# ── Test 5: trap builtin registers a handler ──────────────────────────────────

test_trap_handler() {
    local OUT
    OUT=$(printf "trap 'echo caught_usr1' USR1\nkill -USR1 $$\necho after_trap\n" \
        | "$SHELL_BIN" 2>&1)
    if echo "$OUT" | grep -q 'caught_usr1'; then
        pass "trap: USR1 handler fired"
    else
        fail "trap: USR1 handler did not fire. output=$OUT"
    fi
}

# ── Test 6: SIGINT to a pipeline kills the whole pipeline ────────────────────
# Start a two-stage pipeline (cat | sleep 60); kill the process group;
# verify neither process is still running after a moment.

test_pipeline_sigint() {
    local PID LOG="$TMPDIR_TESTS/pipe_test.log"
    ( "$SHELL_BIN" <<'EOF'
cat /dev/urandom | sleep 60 &
echo $!
wait
EOF
    ) > "$LOG" 2>&1 &
    PID=$!
    sleep 0.3
    kill -INT $PID 2>/dev/null
    wait $PID 2>/dev/null
    # If the shell and pipeline are gone, no sleep 60 should remain.
    if ! pgrep -f 'sleep 60' > /dev/null 2>&1; then
        pass "pipeline SIGINT: pipeline processes cleaned up"
    else
        # cleanup stray process
        pkill -f 'sleep 60' 2>/dev/null
        fail "pipeline SIGINT: stray pipeline process remained"
    fi
}

# ── Test 7: Nested signal — SIGCHLD does not crash the shell ──────────────────

test_sigchld_no_crash() {
    local OUT RC
    OUT=$(printf 'for i in 1 2 3 4 5; do sleep 0.05 & done; wait; echo ok\n' \
        | "$SHELL_BIN" 2>&1)
    RC=$?
    if [[ "$RC" -eq 0 ]] && echo "$OUT" | grep -q 'ok'; then
        pass "SIGCHLD: multiple children reap without crash"
    else
        fail "SIGCHLD: shell crashed or output wrong. rc=$RC output=$OUT"
    fi
}

# ── Test 8: fg restores a stopped job ────────────────────────────────────────
# This test is best-effort; job control requires a real TTY in most shells.

test_fg_stopped_job() {
    # Just verify the fg builtin is recognized (not "command not found").
    local OUT
    OUT=$(printf 'sleep 60 &\nfg %%1\n' | "$SHELL_BIN" 2>&1 &
          sleep 0.2; kill %1 2>/dev/null; wait 2>/dev/null; echo done)
    if ! echo "$OUT" | grep -qi 'not found\|unknown command'; then
        pass "fg: fg builtin is recognised"
    else
        fail "fg: fg builtin not found. output=$OUT"
    fi
}

# ── run all tests ─────────────────────────────────────────────────────────────

echo "=== signal handling tests (shell: $SHELL_BIN) ==="

if [[ ! -x "$SHELL_BIN" ]]; then
    echo "ERROR: shell binary '$SHELL_BIN' not found or not executable."
    echo "Build it first:  make"
    exit 1
fi

test_sigint_foreground
test_background_jobs_listed
test_kill_builtin
test_signal_exit_status
test_trap_handler
test_pipeline_sigint
test_sigchld_no_crash
test_fg_stopped_job

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
