#!/bin/bash
#
# Check OVN ACL Count on Live Cluster
#
# This script provides multiple methods to check ACL counts in OVN
#

set -e

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

Check OVN ACL count on the live cluster using various methods.

OPTIONS:
    --method METHOD     Method to use: ovn-nbctl, db-exec, or all (default: all)
    --show-acls         Show sample ACL entries (first 10)
    --by-port-group     Group ACLs by port group
    --help              Show this help

METHODS:
    ovn-nbctl           Use ovn-nbctl from ovnkube-master pod (fastest)
    db-exec             Execute SQL directly on OVN database
    all                 Try all methods and compare results

EXAMPLES:
    # Quick count using ovn-nbctl
    $0 --method ovn-nbctl

    # Count and show sample ACLs
    $0 --method ovn-nbctl --show-acls

    # Count ACLs grouped by port group
    $0 --by-port-group

    # Try all methods
    $0 --method all

EOF
}

# Parse arguments
METHOD="all"
SHOW_ACLS=false
BY_PORT_GROUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --method)
            METHOD="$2"
            shift 2
            ;;
        --show-acls)
            SHOW_ACLS=true
            shift
            ;;
        --by-port-group)
            BY_PORT_GROUP=true
            shift
            ;;
        --help|-h)
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

# Find ovnkube pod (master or node)
log_info "Finding OVN pod..."
MASTER_POD=$(oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-master --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z "$MASTER_POD" ]]; then
    log_warn "No ovnkube-master pod found, trying ovnkube-node..."
    MASTER_POD=$(oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-node --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
fi

if [[ -z "$MASTER_POD" ]]; then
    log_error "No running ovnkube pods found"
    exit 1
fi

log_info "Using pod: $MASTER_POD"
echo ""

# Method 1: ovn-nbctl list ACL
check_acls_ovn_nbctl() {
    log_info "Method 1: Using ovn-nbctl list ACL"
    echo "Command: oc exec -n openshift-ovn-kubernetes $MASTER_POD -c ovnkube-controller -- ovn-nbctl list ACL"
    echo ""

    ACL_COUNT=$(oc exec -n openshift-ovn-kubernetes "$MASTER_POD" -c ovnkube-controller -- ovn-nbctl list ACL 2>/dev/null | grep "^_uuid" | wc -l)

    echo -e "${BLUE}Total ACL Count:${NC} ${GREEN}$ACL_COUNT${NC}"

    if [[ "$SHOW_ACLS" == "true" ]]; then
        echo ""
        log_info "Sample ACL entries (first 10):"
        oc exec -n openshift-ovn-kubernetes "$MASTER_POD" -c ovnkube-controller -- ovn-nbctl list ACL 2>/dev/null | head -100
    fi
}

# Method 2: Direct database query
check_acls_db_exec() {
    log_info "Method 2: Using direct database query"
    echo "Command: oc exec -n openshift-ovn-kubernetes $MASTER_POD -c ovnkube-controller -- ovn-nbctl --db=unix:/var/run/ovn/ovnnb_db.sock --no-leader-only --columns=_uuid list ACL"
    echo ""

    ACL_COUNT=$(oc exec -n openshift-ovn-kubernetes "$MASTER_POD" -c ovnkube-controller -- ovn-nbctl --db=unix:/var/run/ovn/ovnnb_db.sock --no-leader-only --columns=_uuid list ACL 2>/dev/null | grep "^_uuid" | wc -l)

    echo -e "${BLUE}Total ACL Count:${NC} ${GREEN}$ACL_COUNT${NC}"
}

# Method 3: Count by port group
check_acls_by_port_group() {
    log_info "Method 3: ACLs grouped by Port Group"
    echo ""

    log_info "Getting port groups..."
    oc exec -n openshift-ovn-kubernetes "$MASTER_POD" -c ovnkube-controller -- ovn-nbctl list Port_Group 2>/dev/null | \
        grep -E "^(_uuid|name|acls)" | \
        awk '
        /^_uuid/ {uuid=$3}
        /^name/ {name=$3; gsub(/"/, "", name)}
        /^acls/ {
            # Extract number of ACLs from array
            acl_count = gsub(/[a-f0-9-]{36}/, "&")
            if (acl_count > 0) {
                printf "%-50s %5d ACLs\n", name, acl_count
                total += acl_count
            }
        }
        END {print "\n" "Total ACLs: " total}
        ' | sort -t: -k2 -rn
}

# Method 4: Count ACLs by type (ingress/egress)
check_acls_by_direction() {
    log_info "Counting ACLs by direction..."
    echo ""

    INGRESS_COUNT=$(oc exec -n openshift-ovn-kubernetes "$MASTER_POD" -c ovnkube-controller -- ovn-nbctl --columns=direction list ACL 2>/dev/null | grep "from-lport" | wc -l)
    EGRESS_COUNT=$(oc exec -n openshift-ovn-kubernetes "$MASTER_POD" -c ovnkube-controller -- ovn-nbctl --columns=direction list ACL 2>/dev/null | grep "to-lport" | wc -l)

    echo -e "${BLUE}Ingress ACLs (from-lport):${NC} ${GREEN}$INGRESS_COUNT${NC}"
    echo -e "${BLUE}Egress ACLs (to-lport):${NC} ${GREEN}$EGRESS_COUNT${NC}"
    echo -e "${BLUE}Total:${NC} ${GREEN}$((INGRESS_COUNT + EGRESS_COUNT))${NC}"
}

# Method 5: Count ACLs by priority
check_acls_by_priority() {
    log_info "Top 10 ACL priorities (by count)..."
    echo ""

    oc exec -n openshift-ovn-kubernetes "$MASTER_POD" -c ovnkube-controller -- ovn-nbctl --columns=priority list ACL 2>/dev/null | \
        grep "^priority" | \
        awk '{print $3}' | \
        sort | uniq -c | sort -rn | head -10 | \
        awk '{printf "Priority %5d: %6d ACLs\n", $2, $1}'
}

# Main execution
echo "=========================================="
echo "OVN ACL Count Check"
echo "=========================================="
echo ""

if [[ "$METHOD" == "ovn-nbctl" || "$METHOD" == "all" ]]; then
    check_acls_ovn_nbctl
    echo ""
fi

if [[ "$METHOD" == "db-exec" || "$METHOD" == "all" ]]; then
    check_acls_db_exec
    echo ""
fi

if [[ "$BY_PORT_GROUP" == "true" || "$METHOD" == "all" ]]; then
    check_acls_by_port_group
    echo ""
fi

if [[ "$METHOD" == "all" ]]; then
    echo "=========================================="
    echo "Additional ACL Statistics"
    echo "=========================================="
    echo ""

    check_acls_by_direction
    echo ""

    check_acls_by_priority
    echo ""
fi

log_info "Done!"
