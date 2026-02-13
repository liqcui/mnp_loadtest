#!/bin/bash
#
# Generate Large-Scale OVN ACLs for Load Testing
#
# This script creates ACLs directly in OVN Northbound database
# to simulate customer's large-scale ACL environment
#

set -e

# Configuration
NAMESPACE="${NAMESPACE:-loadtest}"
ACL_COUNT="${ACL_COUNT:-1000}"
SWITCH_NAME="${SWITCH_NAME:-}"
PRIORITY="${PRIORITY:-1000}"
ACTION="${ACTION:-allow-related}"
DIRECTION="${DIRECTION:-both}"  # ingress, egress, or both
BASE_IP="${BASE_IP:-192.168.10}"
START_PORT="${START_PORT:-3306}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Generate large-scale OVN ACLs for load testing

OPTIONS:
    --acl-count N           Number of ACLs to generate (default: 1000)
    --switch NAME           Logical switch name (auto-detect if not specified)
    --priority N            ACL priority (default: 1000)
    --action ACTION         ACL action: allow-related, allow, drop, reject (default: allow-related)
    --direction DIR         Direction: ingress, egress, or both (default: both)
    --base-ip X.X.X         Base IP for rules (default: 192.168.10)
    --start-port N          Starting port number (default: 3306)
    --dry-run               Show commands without executing
    --count-only            Count existing ACLs and exit
    --clean                 Remove all test ACLs
    -h, --help              Show this help

EXAMPLES:
    # Generate 1000 ACLs (500 ingress + 500 egress)
    $0 --acl-count 1000

    # Generate 2000 ACLs on specific switch
    $0 --acl-count 2000 --switch openshift-qe-018.lab.eng.rdu2.redhat.com

    # Count existing ACLs
    $0 --count-only

    # Clean up test ACLs
    $0 --clean

    # Dry run to see commands
    $0 --acl-count 100 --dry-run

EOF
}

# Parse arguments
DRY_RUN=false
COUNT_ONLY=false
CLEAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --acl-count)
            ACL_COUNT="$2"
            shift 2
            ;;
        --switch)
            SWITCH_NAME="$2"
            shift 2
            ;;
        --priority)
            PRIORITY="$2"
            shift 2
            ;;
        --action)
            ACTION="$2"
            shift 2
            ;;
        --direction)
            DIRECTION="$2"
            shift 2
            ;;
        --base-ip)
            BASE_IP="$2"
            shift 2
            ;;
        --start-port)
            START_PORT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --count-only)
            COUNT_ONLY=true
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Get ovnkube pod
OVNKUBE_POD=$(oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-node -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "$OVNKUBE_POD" ]]; then
    log_error "Could not find ovnkube-node pod"
    exit 1
fi

log_info "Using OVN pod: $OVNKUBE_POD"

# Function to execute ovn-nbctl command
ovn_exec() {
    local cmd="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] $cmd"
    else
        oc exec -n openshift-ovn-kubernetes "$OVNKUBE_POD" -c ovnkube-controller -- \
            bash -c "ovn-nbctl --no-leader-only $cmd"
    fi
}

# Count existing ACLs
count_acls() {
    log_info "Counting existing ACLs..." >&2
    local total=$(oc exec -n openshift-ovn-kubernetes "$OVNKUBE_POD" -c ovnkube-controller -- \
        ovn-nbctl --no-leader-only --format=csv --no-headings --columns=_uuid list acl 2>/dev/null | wc -l | tr -d ' ')
    echo "$total"
}

# Clean up test ACLs
cleanup_acls() {
    log_info "Cleaning up test ACLs..."

    # Find ACLs with our test external_ids
    local test_acls=$(oc exec -n openshift-ovn-kubernetes "$OVNKUBE_POD" -c ovnkube-controller -- \
        ovn-nbctl --no-leader-only --format=csv --no-headings --columns=_uuid \
        find acl 'external_ids{>=}{"test-acl"="loadtest"}' 2>/dev/null)

    if [[ -z "$test_acls" ]]; then
        log_info "No test ACLs found to clean up"
        return
    fi

    local count=0
    while IFS= read -r uuid; do
        if [[ -n "$uuid" ]]; then
            ovn_exec "destroy acl $uuid"
            ((count++))
        fi
    done <<< "$test_acls"

    log_info "Removed $count test ACLs"
}

# Count only mode
if [[ "$COUNT_ONLY" == "true" ]]; then
    total=$(count_acls)
    log_info "Total ACLs in OVN database: $total"
    exit 0
fi

# Clean mode
if [[ "$CLEAN" == "true" ]]; then
    cleanup_acls
    total=$(count_acls)
    log_info "Total ACLs after cleanup: $total"
    exit 0
fi

# Auto-detect switch if not specified
if [[ -z "$SWITCH_NAME" ]]; then
    log_info "Auto-detecting logical switch..."
    SWITCH_NAME=$(oc exec -n openshift-ovn-kubernetes "$OVNKUBE_POD" -c ovnkube-controller -- \
        ovn-nbctl --no-leader-only ls-list 2>/dev/null | \
        grep -v "ext_\|join\|transit" | head -1 | sed 's/.* (\(.*\))/\1/')

    if [[ -z "$SWITCH_NAME" ]]; then
        log_error "Could not auto-detect logical switch"
        exit 1
    fi
    log_info "Using logical switch: $SWITCH_NAME"
else
    log_info "Using specified logical switch: $SWITCH_NAME"
fi

# Count before
log_info "Counting ACLs before generation..."
BEFORE_COUNT=$(count_acls)
log_info "ACLs before: $BEFORE_COUNT"

echo ""
log_info "Generating $ACL_COUNT ACLs..."
log_info "  Switch: $SWITCH_NAME"
log_info "  Priority: $PRIORITY"
log_info "  Action: $ACTION"
log_info "  Direction: $DIRECTION"
echo ""

# Calculate ACLs per direction
if [[ "$DIRECTION" == "both" ]]; then
    INGRESS_COUNT=$((ACL_COUNT / 2))
    EGRESS_COUNT=$((ACL_COUNT - INGRESS_COUNT))
elif [[ "$DIRECTION" == "ingress" ]]; then
    INGRESS_COUNT=$ACL_COUNT
    EGRESS_COUNT=0
else
    INGRESS_COUNT=0
    EGRESS_COUNT=$ACL_COUNT
fi

# Generate Ingress ACLs
if [[ $INGRESS_COUNT -gt 0 ]]; then
    log_info "Generating $INGRESS_COUNT ingress ACLs..."

    for ((i=0; i<$INGRESS_COUNT; i++)); do
        IP_SUFFIX=$((10 + (i % 240)))
        PORT=$((START_PORT + i))
        SRC_IP="${BASE_IP}.${IP_SUFFIX}"

        MATCH="ip4.src == ${SRC_IP} && tcp.dst == ${PORT}"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Creating ingress ACL $i: ${MATCH}"
        else
            oc exec -n openshift-ovn-kubernetes "$OVNKUBE_POD" -c ovnkube-controller -- \
                ovn-nbctl --no-leader-only -- --id=@acl create acl priority=${PRIORITY} direction=from-lport \
                "match=\"${MATCH}\"" action=${ACTION} \
                external_ids:test-acl=loadtest external_ids:test-type=ingress external_ids:test-id=${i} \
                -- add logical_switch "${SWITCH_NAME}" acls @acl > /dev/null 2>&1
        fi

        if [[ $((i % 100)) -eq 0 ]]; then
            echo -ne "\r  Progress: $i/$INGRESS_COUNT ingress ACLs"
        fi
    done
    echo ""
    log_info "✓ Created $INGRESS_COUNT ingress ACLs"
fi

# Generate Egress ACLs
if [[ $EGRESS_COUNT -gt 0 ]]; then
    log_info "Generating $EGRESS_COUNT egress ACLs..."

    for ((i=0; i<$EGRESS_COUNT; i++)); do
        IP_SUFFIX=$((10 + (i % 240)))
        PORT=$((START_PORT + i))
        DST_IP="${BASE_IP}.${IP_SUFFIX}"

        MATCH="ip4.dst == ${DST_IP} && tcp.dst == ${PORT}"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Creating egress ACL $i: ${MATCH}"
        else
            oc exec -n openshift-ovn-kubernetes "$OVNKUBE_POD" -c ovnkube-controller -- \
                ovn-nbctl --no-leader-only -- --id=@acl create acl priority=${PRIORITY} direction=to-lport \
                "match=\"${MATCH}\"" action=${ACTION} \
                external_ids:test-acl=loadtest external_ids:test-type=egress external_ids:test-id=${i} \
                -- add logical_switch "${SWITCH_NAME}" acls @acl > /dev/null 2>&1
        fi

        if [[ $((i % 100)) -eq 0 ]]; then
            echo -ne "\r  Progress: $i/$EGRESS_COUNT egress ACLs"
        fi
    done
    echo ""
    log_info "✓ Created $EGRESS_COUNT egress ACLs"
fi

# Count after
log_info "Counting ACLs after generation..."
AFTER_COUNT=$(count_acls)
ADDED=$((AFTER_COUNT - BEFORE_COUNT))

echo ""
log_info "=========================================="
log_info "ACL Generation Complete"
log_info "=========================================="
log_info "ACLs before:  $BEFORE_COUNT"
log_info "ACLs after:   $AFTER_COUNT"
log_info "ACLs added:   $ADDED"
log_info "  - Ingress:  $INGRESS_COUNT"
log_info "  - Egress:   $EGRESS_COUNT"
echo ""

if [[ "$DRY_RUN" == "false" ]]; then
    log_info "Verification commands:"
    echo "  # Count total ACLs:"
    echo "  $0 --count-only"
    echo ""
    echo "  # View test ACLs:"
    echo "  oc exec -n openshift-ovn-kubernetes $OVNKUBE_POD -c ovnkube-controller -- \\"
    echo "    ovn-nbctl --no-leader-only find acl 'external_ids{>=}{\"test-acl\"=\"loadtest\"}'"
    echo ""
    echo "  # Clean up test ACLs:"
    echo "  $0 --clean"
fi
