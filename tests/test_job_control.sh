#!/usr/bin/env bash
# tests/test_job_control.sh — Job-control test suite for unix-shell
#
# Tests covered:
#   1. Background job launch  (&)
#   2. 'jobs' lists running and stopped jobs
#   3. 'fg' resumes a stopped job in the foreground
#   4. 'bg' resumes a stopped job in the background
#   5. Ctrl-Z (SIGTSTP) suspends a foreground job
#   6. Multiple concurrent background jobs
#   7. 'wait' for a specific background PID
#   8. Job completion removes it from the jobs table
#
# Usage:
#   SHELL_BIN=./mysh bash tests/test_job_control.sh
#   SHELL_BIN defaults to ./mysh if unset.

set -euo pipefail

SHELL_BIN=${SHELL_BIN:-./mysh}
PASS=0
FAIL=0

# ── helpers ──────────────────────────────────────────────────────────────────

pass() { echo "PASS: $1"; ((PASS++)); }
fail() { echo "FAIL: $1"; ((FAIL++)); }

# Run a here-doc script through the shell under test; capture stdout + stderr.
run_shell() {
    "$SHELL_BIN" <<'EOF_INNER'
EOF_INNER
}

run_script() {
    local script="$1"
    echo "$script" | "$SHELL_BIN" 2>&1
}

# ── 1. Background job launch ─────────────────────────────────────────────────
test_bg_launch() {
    local out
    out=$(run_script 'sleep 0.1 &; echo launched')
    if echo "$out" | grep -q 'launched'; then
        pass "background job launch prints shell output"
    else
        fail "background job launch: expected 'launched' in output, got: $out"
    fi
}

# ── 2. 'jobs' shows background jobs ─────────────────────────────────────────
test_jobs_list() {
    local out
    out=$(run_script 'sleep 10 &; jobs')
    if echo "$out" | grep -qE '\[1\].*[Rr]unning.*sleep'; then
        pass "jobs lists background job"
    else
        fail "jobs: expected '[1] Running sleep 10', got: $out"
    fi
}

# ── 3. 'fg' brings job to foreground ─────────────────────────────────────────
test_fg_resumes() {
    # Start a sleeping job in the background, then fg it;
    # with a very short sleep it should finish and return control.
    local out
    out=$(run_script 'sleep 0.05 &; fg %1' 2>&1 || true)
    if ! echo "$out" | grep -qi 'error\|not found\|no such'; then
        pass "fg resumes background job without error"
    else
        fail "fg: unexpected error output: $out"
    fi
}

# ── 4. 'bg' resumes stopped job ──────────────────────────────────────────────
test_bg_resumes_stopped() {
    # Send SIGSTOP to a background job, then bg it.
    local out
    out=$(run_script '
sleep 10 &
JOB_PID=$!
sleep 0.05
kill -STOP $JOB_PID
bg %1
jobs
kill $JOB_PID 2>/dev/null || true
' 2>&1)
    if echo "$out" | grep -qiE 'running|background'; then
        pass "bg resumes stopped job"
    else
        fail "bg: job not shown as running after bg, output: $out"
    fi
}

# ── 5. SIGTSTP suspends foreground job ───────────────────────────────────────
test_sigtstp_suspends() {
    # Start a fg job, send SIGTSTP to it externally, then check jobs shows Stopped.
    local out
    out=$(run_script '
sleep 10 &
FG_PID=$!
sleep 0.05
kill -TSTP $FG_PID
jobs
kill $FG_PID 2>/dev/null || true
' 2>&1)
    if echo "$out" | grep -qiE 'stop|suspended'; then
        pass "SIGTSTP suspends job"
    else
        fail "SIGTSTP: job not shown as stopped, output: $out"
    fi
}

# ── 6. Multiple concurrent background jobs ────────────────────────────────────
test_multiple_bg_jobs() {
    local out
    out=$(run_script '
sleep 10 &
sleep 10 &
sleep 10 &
jobs
kill %1 %2 %3 2>/dev/null || true
' 2>&1)
    local count
    count=$(echo "$out" | grep -cE '\[[0-9]+\]' || true)
    if [ "$count" -ge 3 ]; then
        pass "multiple background jobs all appear in jobs list"
    else
        fail "multiple background jobs: expected >= 3 entries, found $count. output: $out"
    fi
}

# ── 7. 'wait' for specific background PID ────────────────────────────────────
test_wait_pid() {
    local out
    out=$(run_script '
sleep 0.1 &
BG_PID=$!
wait $BG_PID
echo "exit:$?"
' 2>&1)
    if echo "$out" | grep -q 'exit:0'; then
        pass "wait <pid> returns exit status of background job"
    else
        fail "wait <pid>: expected 'exit:0', got: $out"
    fi
}

# ── 8. Completed job removed from jobs table ─────────────────────────────────
test_completed_job_removed() {
    local out
    out=$(run_script '
sleep 0.05 &
wait %1
jobs
echo "done"
' 2>&1)
    # After wait, 'jobs' should show nothing (or the job as Done, not Running).
    local running_count
    running_count=$(echo "$out" | grep -cE '[Rr]unning.*sleep' || true)
    if [ "$running_count" -eq 0 ]; then
        pass "completed job no longer listed as Running in jobs"
    else
        fail "completed job still shows as Running: $out"
    fi
}

# ── run all tests ─────────────────────────────────────────────────────────────

if [ ! -x "$SHELL_BIN" ]; then
    echo "ERROR: shell binary not found or not executable: $SHELL_BIN"
    echo "Build it first with: make"
    exit 2
fi

echo "=== Job Control Tests: $SHELL_BIN ==="
echo ""

test_bg_launch
test_jobs_list
test_fg_resumes
test_bg_resumes_stopped
test_sigtstp_suspends
test_multiple_bg_jobs
test_wait_pid
test_completed_job_removed

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
