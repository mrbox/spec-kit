#!/usr/bin/env bash

# Task structure validation script
#
# Validates the tasks/ directory structure for consistency:
# - JSONL validity (each line is valid JSON)
# - File references (each file in JSONL exists)
# - No orphan files (no task files without JSONL entry)
# - Frontmatter sync (task file metadata matches JSONL)
# - Dependency validity (all depends_on refs exist, no cycles)
# - Status coherence (done tasks have all dependencies done)
#
# Usage: ./validate-tasks.sh [OPTIONS]
#
# OPTIONS:
#   --json      Output results in JSON format
#   --verbose   Show detailed information for each check
#   --help, -h  Show help message

set -e

# Parse command line arguments
JSON_MODE=false
VERBOSE=false

for arg in "$@"; do
    case "$arg" in
        --json)
            JSON_MODE=true
            ;;
        --verbose)
            VERBOSE=true
            ;;
        --help|-h)
            cat << 'EOF'
Usage: validate-tasks.sh [OPTIONS]

Validates the tasks/ directory structure for consistency.

OPTIONS:
  --json      Output results in JSON format
  --verbose   Show detailed information for each check
  --help, -h  Show this help message

CHECKS PERFORMED:
  1. JSONL validity - Each line in tasks.jsonl is valid JSON
  2. File references - Each file referenced in JSONL exists
  3. No orphans - No task files exist without JSONL entry
  4. Frontmatter sync - Task file frontmatter matches JSONL data
  5. Dependency validity - All depends_on refs exist, no cycles
  6. Status coherence - Done tasks have all dependencies done

EXIT CODES:
  0 - All checks passed
  1 - One or more checks failed
  2 - Tasks directory not found

EOF
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option '$arg'. Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

# Source common functions
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Get feature paths
eval $(get_feature_paths)

TASKS_DIR="$FEATURE_DIR/tasks"
TASKS_INDEX="$TASKS_DIR/tasks.jsonl"

# Check if tasks directory exists
if [[ ! -d "$TASKS_DIR" ]]; then
    if $JSON_MODE; then
        echo '{"valid":false,"error":"Tasks directory not found","checks":[]}'
    else
        echo "ERROR: Tasks directory not found: $TASKS_DIR" >&2
        echo "Run /speckit.tasks first to create the task structure." >&2
    fi
    exit 2
fi

# Check if tasks.jsonl exists
if [[ ! -f "$TASKS_INDEX" ]]; then
    if $JSON_MODE; then
        echo '{"valid":false,"error":"tasks.jsonl not found","checks":[]}'
    else
        echo "ERROR: tasks.jsonl not found: $TASKS_INDEX" >&2
        echo "Run /speckit.tasks first to create the task structure." >&2
    fi
    exit 2
fi

# Initialize validation results
ERRORS=()
WARNINGS=()
CHECKS_PASSED=0
CHECKS_FAILED=0

log_error() {
    ERRORS+=("$1")
    ((CHECKS_FAILED++)) || true
}

log_warning() {
    WARNINGS+=("$1")
}

log_pass() {
    ((CHECKS_PASSED++)) || true
    if $VERBOSE && ! $JSON_MODE; then
        echo "  ✓ $1"
    fi
}

# ============================================================================
# Check 1: JSONL Validity
# ============================================================================
if $VERBOSE && ! $JSON_MODE; then
    echo "Checking JSONL validity..."
fi

LINE_NUM=0
TASK_IDS=()
TASK_FILES=()
TASK_DEPS=()
TASK_STATUS=()

while IFS= read -r line || [[ -n "$line" ]]; do
    ((LINE_NUM++)) || true

    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Validate JSON
    if ! echo "$line" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        log_error "Line $LINE_NUM: Invalid JSON"
        continue
    fi

    # Extract fields
    id=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))")
    file=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('file',''))")
    status=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))")
    deps=$(echo "$line" | python3 -c "import json,sys; print(','.join(json.load(sys.stdin).get('depends_on',[])))")

    if [[ -z "$id" ]]; then
        log_error "Line $LINE_NUM: Missing 'id' field"
        continue
    fi

    if [[ -z "$file" ]]; then
        log_error "Line $LINE_NUM: Missing 'file' field for task $id"
        continue
    fi

    TASK_IDS+=("$id")
    TASK_FILES+=("$file")
    TASK_STATUS+=("$status")
    TASK_DEPS+=("$deps")

done < "$TASKS_INDEX"

if [[ $LINE_NUM -eq 0 ]]; then
    log_error "tasks.jsonl is empty"
else
    log_pass "JSONL validity: $LINE_NUM lines parsed"
fi

# ============================================================================
# Check 2: File References
# ============================================================================
if $VERBOSE && ! $JSON_MODE; then
    echo "Checking file references..."
fi

for i in "${!TASK_IDS[@]}"; do
    task_file="$TASKS_DIR/${TASK_FILES[$i]}"
    if [[ ! -f "$task_file" ]]; then
        log_error "Task ${TASK_IDS[$i]}: Referenced file not found: ${TASK_FILES[$i]}"
    else
        log_pass "Task ${TASK_IDS[$i]}: File exists"
    fi
done

# ============================================================================
# Check 3: No Orphan Files
# ============================================================================
if $VERBOSE && ! $JSON_MODE; then
    echo "Checking for orphan files..."
fi

for task_file in "$TASKS_DIR"/T*.md; do
    [[ ! -f "$task_file" ]] && continue

    filename=$(basename "$task_file")
    found=false

    for ref_file in "${TASK_FILES[@]}"; do
        if [[ "$filename" == "$ref_file" ]]; then
            found=true
            break
        fi
    done

    if ! $found; then
        log_error "Orphan file (not in tasks.jsonl): $filename"
    fi
done

log_pass "Orphan check complete"

# ============================================================================
# Check 4: Frontmatter Sync
# ============================================================================
if $VERBOSE && ! $JSON_MODE; then
    echo "Checking frontmatter sync..."
fi

for i in "${!TASK_IDS[@]}"; do
    task_file="$TASKS_DIR/${TASK_FILES[$i]}"
    [[ ! -f "$task_file" ]] && continue

    # Extract frontmatter id
    fm_id=$(sed -n '/^---$/,/^---$/p' "$task_file" | grep -E '^id:' | sed 's/^id:[[:space:]]*//' | tr -d '\r')

    if [[ "$fm_id" != "${TASK_IDS[$i]}" ]]; then
        log_error "Task ${TASK_IDS[$i]}: Frontmatter id mismatch (found: '$fm_id')"
    else
        log_pass "Task ${TASK_IDS[$i]}: Frontmatter sync OK"
    fi

    # Extract frontmatter status
    fm_status=$(sed -n '/^---$/,/^---$/p' "$task_file" | grep -E '^status:' | sed 's/^status:[[:space:]]*//' | tr -d '\r')

    if [[ "$fm_status" != "${TASK_STATUS[$i]}" ]]; then
        log_warning "Task ${TASK_IDS[$i]}: Status mismatch (JSONL: '${TASK_STATUS[$i]}', file: '$fm_status')"
    fi
done

# ============================================================================
# Check 5: Dependency Validity
# ============================================================================
if $VERBOSE && ! $JSON_MODE; then
    echo "Checking dependency validity..."
fi

# Check all deps exist
for i in "${!TASK_IDS[@]}"; do
    deps="${TASK_DEPS[$i]}"
    [[ -z "$deps" ]] && continue

    IFS=',' read -ra dep_array <<< "$deps"
    for dep in "${dep_array[@]}"; do
        found=false
        for id in "${TASK_IDS[@]}"; do
            if [[ "$dep" == "$id" ]]; then
                found=true
                break
            fi
        done

        if ! $found; then
            log_error "Task ${TASK_IDS[$i]}: Unknown dependency '$dep'"
        fi
    done
done

# Check for cycles (simple DFS)
check_cycle() {
    local task_id="$1"
    local -a visiting=("${@:2}")

    # Check if already visiting (cycle)
    for v in "${visiting[@]}"; do
        if [[ "$v" == "$task_id" ]]; then
            return 1
        fi
    done

    # Find task index
    local idx=-1
    for i in "${!TASK_IDS[@]}"; do
        if [[ "${TASK_IDS[$i]}" == "$task_id" ]]; then
            idx=$i
            break
        fi
    done

    [[ $idx -eq -1 ]] && return 0

    local deps="${TASK_DEPS[$idx]}"
    [[ -z "$deps" ]] && return 0

    visiting+=("$task_id")

    IFS=',' read -ra dep_array <<< "$deps"
    for dep in "${dep_array[@]}"; do
        if ! check_cycle "$dep" "${visiting[@]}"; then
            return 1
        fi
    done

    return 0
}

for id in "${TASK_IDS[@]}"; do
    if ! check_cycle "$id"; then
        log_error "Circular dependency detected involving task $id"
    fi
done

log_pass "Dependency check complete"

# ============================================================================
# Check 6: Status Coherence
# ============================================================================
if $VERBOSE && ! $JSON_MODE; then
    echo "Checking status coherence..."
fi

for i in "${!TASK_IDS[@]}"; do
    [[ "${TASK_STATUS[$i]}" != "done" ]] && continue

    deps="${TASK_DEPS[$i]}"
    [[ -z "$deps" ]] && continue

    IFS=',' read -ra dep_array <<< "$deps"
    for dep in "${dep_array[@]}"; do
        # Find dep status
        for j in "${!TASK_IDS[@]}"; do
            if [[ "${TASK_IDS[$j]}" == "$dep" ]]; then
                if [[ "${TASK_STATUS[$j]}" != "done" ]]; then
                    log_warning "Task ${TASK_IDS[$i]} is done but dependency $dep is not"
                fi
                break
            fi
        done
    done
done

log_pass "Status coherence check complete"

# ============================================================================
# Output Results
# ============================================================================
VALID=true
[[ ${#ERRORS[@]} -gt 0 ]] && VALID=false

if $JSON_MODE; then
    # Build JSON output
    errors_json="["
    for i in "${!ERRORS[@]}"; do
        [[ $i -gt 0 ]] && errors_json+=","
        errors_json+="\"${ERRORS[$i]}\""
    done
    errors_json+="]"

    warnings_json="["
    for i in "${!WARNINGS[@]}"; do
        [[ $i -gt 0 ]] && warnings_json+=","
        warnings_json+="\"${WARNINGS[$i]}\""
    done
    warnings_json+="]"

    printf '{"valid":%s,"tasks":%d,"checks_passed":%d,"checks_failed":%d,"errors":%s,"warnings":%s}\n' \
        "$VALID" "${#TASK_IDS[@]}" "$CHECKS_PASSED" "$CHECKS_FAILED" "$errors_json" "$warnings_json"
else
    echo ""
    echo "=== Validation Results ==="
    echo "Tasks: ${#TASK_IDS[@]}"
    echo "Checks passed: $CHECKS_PASSED"
    echo "Checks failed: $CHECKS_FAILED"
    echo ""

    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo "Errors:"
        for err in "${ERRORS[@]}"; do
            echo "  ✗ $err"
        done
        echo ""
    fi

    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        echo "Warnings:"
        for warn in "${WARNINGS[@]}"; do
            echo "  ⚠ $warn"
        done
        echo ""
    fi

    if $VALID; then
        echo "✓ All checks passed"
    else
        echo "✗ Validation failed"
    fi
fi

$VALID && exit 0 || exit 1
