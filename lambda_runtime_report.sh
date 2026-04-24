#!/usr/bin/env bash
# =============================================================================
# lambda_runtime_report.sh
#
# Lists every Lambda function and its runtime across all enabled AWS regions.
#
# Usage:
#   source lambda_runtime_report.sh && lambda_runtime_report
#   bash lambda_runtime_report.sh            # runs directly too
#
# Options (env vars):
#   AWS_PROFILE=my-profile  bash lambda_runtime_report.sh
#   REGIONS="us-east-1 eu-west-1"  bash lambda_runtime_report.sh
#
# Requirements:
#   aws CLI v2  (https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
#   jq          (optional — only used for the summary; apt/brew install jq)
# =============================================================================

lambda_runtime_report() {
    # ── Colour codes (degrade gracefully if not a TTY) ─────────────────────
    local RED='' YELLOW='' CYAN='' BOLD='' RESET=''
    if [[ -t 1 ]]; then
        RED='\033[0;31m'; YELLOW='\033[0;33m'
        CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
    fi

    # ── Verify aws CLI is available ─────────────────────────────────────────
    if ! command -v aws &>/dev/null; then
        echo "Error: 'aws' CLI not found. Install it from https://aws.amazon.com/cli/" >&2
        return 1
    fi

    # ── Verify credentials ──────────────────────────────────────────────────
    if ! aws sts get-caller-identity --output text &>/dev/null; then
        echo "Error: No valid AWS credentials found." >&2
        echo "  Set AWS_PROFILE, AWS_ACCESS_KEY_ID/SECRET, or configure ~/.aws/credentials" >&2
        return 1
    fi

    # ── Resolve region list ─────────────────────────────────────────────────
    local regions
    if [[ -n "${REGIONS:-}" ]]; then
        # Allow caller to override: REGIONS="us-east-1 eu-west-1" ./script.sh
        read -ra regions <<< "$REGIONS"
    else
        echo -e "${CYAN}Discovering enabled regions...${RESET}" >&2
        mapfile -t regions < <(
            aws ec2 describe-regions \
                --filters "Name=opt-in-status,Values=opt-in-not-required,opted-in" \
                --query "Regions[].RegionName" \
                --output text \
            | tr '\t' '\n' \
            | sort
        )
    fi

    if [[ ${#regions[@]} -eq 0 ]]; then
        echo "Error: Could not retrieve region list." >&2
        return 1
    fi

    local total_regions=${#regions[@]}
    echo -e "${CYAN}Scanning ${BOLD}${total_regions}${RESET}${CYAN} region(s)...${RESET}" >&2
    echo ""

    # ── Deprecated runtimes (AWS EOL list) ─────────────────────────────────
    local deprecated_runtimes=(
        nodejs nodejs4.3 nodejs4.3-edge nodejs6.10 nodejs8.10
        nodejs10.x nodejs12.x nodejs14.x
        python2.7 python3.6 python3.7 python3.8
        dotnetcore1.0 dotnetcore2.0 dotnetcore2.1 dotnetcore3.1 dotnet5.0
        ruby2.5 ruby2.7
        java8
        go1.x
    )

    # Build a pipe-delimited pattern for grep matching
    local deprecated_pattern
    deprecated_pattern=$(printf '%s|' "${deprecated_runtimes[@]}")
    deprecated_pattern="${deprecated_pattern%|}"   # trim trailing pipe

    # ── Accumulators ────────────────────────────────────────────────────────
    local total_functions=0
    local total_deprecated=0
    local all_runtimes=()          # flat list of every runtime seen
    local regions_with_functions=()

    # ── Main loop ───────────────────────────────────────────────────────────
    local idx=0
    for region in "${regions[@]}"; do
        (( idx++ ))
        printf "\r${CYAN}  [%d/%d] %-20s${RESET}" "$idx" "$total_regions" "$region" >&2

        # Fetch functions; skip region silently on access-denied
        local raw
        raw=$(aws lambda list-functions \
                --region "$region" \
                --query "Functions[].[FunctionName, Runtime]" \
                --output table \
                2>/dev/null)

        # Skip regions that returned nothing (no functions or no access)
        [[ -z "$raw" || "$raw" == *"None"* ]] && continue

        # Count functions in this region (lines that start with |  text)
        local count
        count=$(echo "$raw" | grep -cE '^\|[[:space:]]+[^-]' || true)
        (( count == 0 )) && continue

        (( total_functions   += count ))
        regions_with_functions+=("$region")

        # Collect runtimes for the summary (strip table borders)
        while IFS= read -r line; do
            local rt
            rt=$(echo "$line" | awk -F'|' '{print $3}' | tr -d ' ')
            [[ -n "$rt" ]] && all_runtimes+=("$rt")
        done < <(echo "$raw" | grep -E '^\|[[:space:]]+[^-]')

        # Count deprecated in this region
        local dep_count
        dep_count=$(echo "$raw" | grep -cE "$deprecated_pattern" || true)
        (( total_deprecated += dep_count ))

        # ── Print region header + table ─────────────────────────────────
        printf "\r%s\n" ""   # clear progress line
        echo -e "${BOLD}${CYAN}══ Region: ${region} (${count} function(s)) ══${RESET}"

        # Annotate deprecated rows with a warning marker
        while IFS= read -r line; do
            if echo "$line" | grep -qE "$deprecated_pattern"; then
                echo -e "${YELLOW}${line}  ⚠ deprecated${RESET}"
            else
                echo "$line"
            fi
        done <<< "$raw"
        echo ""
    done

    # Clear the progress line cleanly after the loop
    printf "\r%-60s\r" "" >&2

    # ── Summary ─────────────────────────────────────────────────────────────
    echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Summary${RESET}"
    echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
    printf "  %-30s %s\n" "Regions scanned:"         "$total_regions"
    printf "  %-30s %s\n" "Regions with functions:"  "${#regions_with_functions[@]}"
    printf "  %-30s %s\n" "Total functions:"         "$total_functions"

    if (( total_deprecated > 0 )); then
        printf "  %-30s ${YELLOW}%s ⚠${RESET}\n" "Deprecated runtimes:" "$total_deprecated"
    else
        printf "  %-30s %s\n" "Deprecated runtimes:" "0"
    fi

    # Runtime frequency table (requires sort + uniq — always available)
    if (( ${#all_runtimes[@]} > 0 )); then
        echo ""
        echo -e "${BOLD}  Runtime breakdown:${RESET}"
        printf '%s\n' "${all_runtimes[@]}" \
            | sort \
            | uniq -c \
            | sort -rn \
            | while read -r count rt; do
                local flag=""
                echo "$rt" | grep -qE "^(${deprecated_pattern})$" && flag=" ${YELLOW}⚠ deprecated${RESET}"
                printf "    %-28s %4d%b\n" "$rt" "$count" "$flag"
            done
    fi

    echo ""
}

# ── Run directly if executed (not sourced) ───────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    lambda_runtime_report
fi