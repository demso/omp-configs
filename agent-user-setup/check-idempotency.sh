#!/usr/bin/env bash
#
# Idempotency smoke harness.
# Runs static checks only; never applies system changes.
# Exits non-zero on any violation.
#

set -euo pipefail

# Resolve SCRIPT_DIR to directory containing this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Repository path (optional)
REPO="${1:-.}"
REPO=$(cd "${REPO}" && pwd)
cd "${REPO}"

declare -a ERRORS=()
declare -a WARNINGS=()

echo "=== Idempotency Smoke Check ==="
echo

# Step 1: Check shell syntax and forbidden operations
echo "Step 1: Syntax and forbidden operations"

# 1a. Check bash syntax for all setup scripts
for script in first.sh second.sh setup.sh; do
    path="${SCRIPT_DIR}/${script}"
    if [ ! -f "${path}" ]; then
        ERRORS+=("Script not found: ${path}")
        continue
    fi

    if ! bash -n "${path}" 2>/dev/null; then
        ERRORS+=("Syntax error in ${path}")
    fi
done

# 1b. Check for sudo in second.sh and setup.sh (actual command execution, not comments)
for script in second.sh setup.sh; do
    path="${SCRIPT_DIR}/${script}"
    [ -f "${path}" ] || continue

    # Extract non-comment, non-empty lines
    non_comment_lines=$(grep -v '^\s*#' "${path}" | grep -v '^[[:space:]]*$')

    # Flag only lines where sudo is the leading command (actual execution)
    while IFS= read -r line; do
        [[ "${line}" =~ ^[[:space:]]*(declare|local|local[[:space:]]+)|^[[:space:]]*(if|case|for|while|function)\b ]] && continue
        [[ "${line}" =~ ^[[:space:]]*sudo[[:space:]]+-l ]] && continue

        if echo "${line}" | grep -qE '\b(sudo|SUDO)\b'; then
            first_word=$(echo "${line}" | awk '{print $1}')
            if [[ "${first_word}" == sudo ]] || [[ "${first_word}" == SUDO ]]; then
                ERRORS+=("sudo found in command in ${path}: ${line:0:80}")
                break
            fi
        fi
    done <<< "${non_comment_lines}"
done

# 1c. Check for fixed writes/removals
# Flag any mktemp targeting /mnt/d/ unless it uses a unique XXXXXX template
# (approved safe write-access probe: mktemp /mnt/d/.agent-write-test.XXXXXX).
if grep -hE 'mktemp[[:space:]]+/mnt/d/' "$SCRIPT_DIR"/first.sh "$SCRIPT_DIR"/second.sh "$SCRIPT_DIR"/setup.sh 2>/dev/null \
    | grep -vE 'XXXXXX' | grep -q '.'; then
    WARNINGS+=("Potential fixed path /mnt/d/ in one of the setup scripts")
fi

if grep -qE '\brm\s+-[fr][rf]\b' "$SCRIPT_DIR"/first.sh "$SCRIPT_DIR"/second.sh "$SCRIPT_DIR"/setup.sh 2>/dev/null; then
    ERRORS+=("rm -rf found in setup scripts")
fi

if grep -qE '\bexec\s+bash\b' "$SCRIPT_DIR"/first.sh "$SCRIPT_DIR"/second.sh "$SCRIPT_DIR"/setup.sh 2>/dev/null; then
    ERRORS+=("Unconditional exec bash found in setup scripts")
fi

# 1d. Check second.sh runs setup.sh without sudo
if grep -qE '\bsudo\s+setup\.sh' "$SCRIPT_DIR"/second.sh 2>/dev/null; then
    ERRORS+=("sudo in second.sh when calling setup.sh")
fi
echo "  ✓ Syntax and forbidden operations checked"
echo

# Step 2: Check shared configuration references
echo "Step 2: Shared configuration references"

# 2a. Verify all three scripts source /etc/agent-setup.conf
for script in "$SCRIPT_DIR"/first.sh "$SCRIPT_DIR"/second.sh "$SCRIPT_DIR"/setup.sh; do
    # Check for source with variable or literal path
    if grep -qE "source.*CONFIG_FILE" "${script}" 2>/dev/null; then
        # Check if the variable is set to /etc/agent-setup.conf
        if grep -qE 'CONFIG_FILE="/etc/agent-setup.conf"' "${script}" 2>/dev/null; then
            # Found it!
            continue
        fi
    fi

    # Also check for direct sourcing
    if grep -qE 'source "/etc/agent-setup\.conf"' "${script}" 2>/dev/null; then
        continue
    fi

    ERRORS+=("Script does not source /etc/agent-setup.conf: ${script}")
done

# 2b. Verify example defines required variables
if grep -qE "APT_MIRROR=\"[^\"]*\"" "$SCRIPT_DIR"/agent-setup.conf.example 2>/dev/null; then
    echo "  ✓ APT_MIRROR defined"
else
    ERRORS+=("APT_MIRROR not found in agent-setup.conf.example")
fi

if grep -qE "PYPI_MIRROR=\"[^\"]*\"" "$SCRIPT_DIR"/agent-setup.conf.example 2>/dev/null; then
    echo "  ✓ PYPI_MIRROR defined"
else
    ERRORS+=("PYPI_MIRROR not found in agent-setup.conf.example")
fi

if grep -qE "NPM_REGISTRY=\"[^\"]*\"" "$SCRIPT_DIR"/agent-setup.conf.example 2>/dev/null; then
    echo "  ✓ NPM_REGISTRY defined"
else
    ERRORS+=("NPM_REGISTRY not found in agent-setup.conf.example")
fi

if grep -qE "TZ_VALUE=\"[^\"]*\"" "$SCRIPT_DIR"/agent-setup.conf.example 2>/dev/null; then
    echo "  ✓ TZ_VALUE defined"
else
    ERRORS+=("TZ_VALUE not found in agent-setup.conf.example")
fi

echo

# Step 3: Summary
echo "Step 3: Summary"

if [ ${#ERRORS[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]; then
    echo "✓ All idempotency checks passed"
    echo
    echo "  No errors, no warnings"
    exit 0
else
    echo "✗ Idempotency checks failed"
    echo
    if [ ${#ERRORS[@]} -gt 0 ]; then
        echo "  ERRORS (${#ERRORS[@]}):"
        printf "    - %s\n" "${ERRORS[@]}" | sort
    fi
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo "  WARNINGS (${#WARNINGS[@]}):"
        printf "    - %s\n" "${WARNINGS[@]}" | sort
    fi
    echo
    exit 1
fi
