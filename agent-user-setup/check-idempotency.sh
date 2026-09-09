#!/usr/bin/env bash
#
# Idempotency smoke harness.
# Runs static checks only; never applies system changes.
# Exits non-zero on any violation.
#

set -euo pipefail

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
    if [ ! -f "${script}" ]; then
        ERRORS+=("Script not found: ${script}")
        continue
    fi

    if ! bash -n "${script}" 2>&1; then
        ERRORS+=("Syntax error in ${script}")
    fi

    # 1b. Check for sudo in second.sh and setup.sh (actual command execution, not comments)
    # Use grep to extract non-comment lines that are not empty
    non_comment_lines=$(grep -v '^\s*#' "${script}" | grep -v '^[[:space:]]*$')

    # Look for sudo followed by a command (not just as part of variable name or sudo listing)
    while IFS= read -r line; do
        # Skip lines that are just variable assignments or function definitions
        [[ "${line}" =~ ^[[:space:]]*(declare|local|local[[:space:]]+)|^[[:space:]]*(if|case|for|while|function)\b ]] && continue

        # Skip sudo -l (list permissions) which is used for sanitization checks
        [[ "${line}" =~ ^[[:space:]]*sudo[[:space:]]+-l ]] && continue

        # Check if line contains sudo (not as part of a variable name like SUDO_*)
        if echo "${line}" | grep -qE '\b(sudo|SUDO)\b'; then
            # Check if sudo is followed by a command (not just as part of error message)
            # Extract the first word after sudo (if any) and check if it's a command
            first_word=$(echo "${line}" | awk '{print $1}')
            if [[ "${first_word}" == sudo ]] || [[ "${first_word}" == SUDO ]]; then
                ERRORS+=("sudo found in command in ${script}: ${line:0:80}")
                break
            fi
        fi
    done <<< "${non_comment_lines}"
done

# 1c. Check for fixed writes/removals
if grep -qE '\b(mktemp\s+/mnt/d/)' first.sh second.sh setup.sh 2>/dev/null; then
    WARNINGS+=("Potential fixed path /mnt/d/ in one of the setup scripts")
fi

if grep -qE '\brm\s+-[fr][rf]\b' first.sh second.sh setup.sh 2>/dev/null; then
    ERRORS+=("rm -rf found in setup scripts")
fi

if grep -qE '\bexec\s+bash\b' first.sh second.sh setup.sh 2>/dev/null; then
    ERRORS+=("Unconditional exec bash found in setup scripts")
fi

# 1d. Check second.sh runs setup.sh without sudo
if grep -qE '\bsudo\s+setup\.sh' second.sh 2>/dev/null; then
    ERRORS+=("sudo in second.sh when calling setup.sh")
fi

echo "  ✓ Syntax and forbidden operations checked"
echo

# Step 2: Check shared configuration references
echo "Step 2: Shared configuration references"

# 2a. Verify all three scripts source /etc/agent-setup.conf
for script in first.sh second.sh setup.sh; do
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
if grep -qE "APT_MIRROR=\"[^\"]*\"" agent-setup.conf.example 2>/dev/null; then
    echo "  ✓ APT_MIRROR defined"
else
    ERRORS+=("APT_MIRROR not found in agent-setup.conf.example")
fi

if grep -qE "PYPI_MIRROR=\"[^\"]*\"" agent-setup.conf.example 2>/dev/null; then
    echo "  ✓ PYPI_MIRROR defined"
else
    ERRORS+=("PYPI_MIRROR not found in agent-setup.conf.example")
fi

if grep -qE "NPM_REGISTRY=\"[^\"]*\"" agent-setup.conf.example 2>/dev/null; then
    echo "  ✓ NPM_REGISTRY defined"
else
    ERRORS+=("NPM_REGISTRY not found in agent-setup.conf.example")
fi

if grep -qE "TZ_VALUE=\"[^\"]*\"" agent-setup.conf.example 2>/dev/null; then
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
