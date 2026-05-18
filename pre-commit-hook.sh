#!/bin/bash
# Pre-commit hook: auto-scrub secrets then scan staged files before committing.
# Install: cp pre-commit-hook.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
#
# Two-pass approach:
#   1. Auto-replace: reads .secret-replacements (real_value=placeholder, one per
#      line). For each staged file containing secrets, backs up the original,
#      applies ALL replacements, re-stages the cleaned version, then restores
#      the original on disk. This means committed files have placeholders but
#      working-tree files keep real values — critical for workspace files that
#      agents read at runtime.
#   2. Safety-net scan: generic + project-specific patterns (.secret-patterns)
#      catch anything the replacement map didn't cover.
#
# Both .secret-replacements and .secret-patterns are gitignored.

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"

# ============================================================
# PASS 1 — Auto-replace known secrets with placeholders
# ============================================================
REPLACE_FILE="$REPO_ROOT/.secret-replacements"
REPLACED=0

if [ -f "$REPLACE_FILE" ]; then
    # Load all replacement pairs into arrays
    declare -a REALS=()
    declare -a PLACEHOLDERS=()
    while IFS= read -r line; do
        line="$(echo "$line" | sed 's/#.*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        real="${line%%=*}"
        placeholder="${line#*=}"
        [ -z "$real" ] || [ -z "$placeholder" ] && continue
        REALS+=("$real")
        PLACEHOLDERS+=("$placeholder")
    done < "$REPLACE_FILE"

    # For each staged file: backup → apply all replacements → stage → restore
    STAGED_FOR_REPLACE=$(git diff --cached --diff-filter=ACM --name-only 2>/dev/null)
    for file in $STAGED_FOR_REPLACE; do
        [ -f "$REPO_ROOT/$file" ] || continue
        NEEDS_SCRUB=0
        for i in "${!REALS[@]}"; do
            if grep -qF "${REALS[$i]}" "$REPO_ROOT/$file"; then
                NEEDS_SCRUB=1
                break
            fi
        done
        if [ "$NEEDS_SCRUB" -eq 1 ]; then
            cp "$REPO_ROOT/$file" "$REPO_ROOT/$file.pre-scrub"
            for i in "${!REALS[@]}"; do
                sed -i "s|${REALS[$i]}|${PLACEHOLDERS[$i]}|g" "$REPO_ROOT/$file"
            done
            git add "$REPO_ROOT/$file"
            mv "$REPO_ROOT/$file.pre-scrub" "$REPO_ROOT/$file"
            echo "AUTO-SCRUBBED: replaced secret in $file"
            REPLACED=1
        fi
    done
fi

# ============================================================
# PASS 2 — Safety-net pattern scan
# ============================================================
PATTERNS=(
    'PRIVATE KEY'
    'BEGIN (RSA|DSA|EC|OPENSSH) PRIVATE KEY'
    'sk-ant-api'
    'Basic [A-Za-z0-9+/=]{20,}'
    'password\s*[:=]\s*["\x27][^"\x27]{4,}'
    'secret\s*[:=]\s*["\x27][^"\x27]{4,}'
    'token\s*[:=]\s*["\x27][^"\x27]{8,}'
)

SECRET_FILE="$REPO_ROOT/.secret-patterns"
if [ -f "$SECRET_FILE" ]; then
    while IFS= read -r line; do
        line="$(echo "$line" | sed 's/#.*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        PATTERNS+=("$line")
    done < "$SECRET_FILE"
fi

STAGED_FILES=$(git diff --cached --diff-filter=ACM --name-only 2>/dev/null)
if [ -z "$STAGED_FILES" ]; then
    exit 0
fi

FAILED=0

for file in $STAGED_FILES; do
    # Skip the hook script itself — it contains detection patterns, not secrets
    [ "$file" = "pre-commit-hook.sh" ] && continue
    for pattern in "${PATTERNS[@]}"; do
        if git show ":$file" 2>/dev/null | grep -qiE "$pattern"; then
            echo "BLOCKED: pattern '$pattern' found in $file"
            FAILED=1
        fi
    done
done

if [ "$FAILED" -eq 1 ]; then
    echo ""
    echo "Commit blocked — potential secrets/PII detected in staged files."
    echo "Fix the flagged files, or if false positive: git commit --no-verify"
    exit 1
fi

if [ "$REPLACED" -eq 1 ]; then
    echo "Auto-scrub complete. Commit proceeding with cleaned files."
fi

exit 0
