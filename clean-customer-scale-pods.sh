#!/bin/bash
#
# Clean up resources created by generate-customer-scale-pods.sh
#
# This script removes:
# - Deployments/Pods with label test=customer-scale
# - MultiNetworkPolicies with label test=customer-scale
# - NetworkAttachmentDefinitions for VLANs
#

set -e

# Configuration
NAMESPACE="${NAMESPACE:-loadtest}"
VLAN_COUNT="${VLAN_COUNT:-9}"
VLAN_START=750

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

Clean up resources created by generate-customer-scale-pods.sh:
- Deployments/Pods with label test=customer-scale
- MultiNetworkPolicies with label test=customer-scale
- NetworkAttachmentDefinitions for VLANs

OPTIONS:
    --namespace NS          Namespace to clean (default: loadtest)
    --vlan-count N          Number of VLANs to delete (default: 9)
    --vlan-start N          Starting VLAN ID (default: 750)
    --deployments-only      Delete only deployments/pods (skip policies and NADs)
    --skip-deployments      Skip deleting deployments/pods
    --skip-policies         Skip deleting multi-networkpolicies
    --skip-nads             Skip deleting network attachment definitions
    --dry-run               Show what would be deleted without deleting
    -h, --help              Show this help

EXAMPLES:
    # Clean all resources in loadtest namespace
    $0

    # Delete only deployments/pods in loadtest namespace
    $0 --deployments-only

    # Clean resources in custom namespace
    $0 --namespace my-namespace

    # Only clean policies and deployments, keep NADs
    $0 --skip-nads

    # Dry run to see what would be deleted
    $0 --dry-run

EOF
}

# Parse arguments
DRY_RUN=false
SKIP_DEPLOYMENTS=false
SKIP_POLICIES=false
SKIP_NADS=false
DEPLOYMENTS_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --vlan-count)
            VLAN_COUNT="$2"
            shift 2
            ;;
        --vlan-start)
            VLAN_START="$2"
            shift 2
            ;;
        --deployments-only)
            DEPLOYMENTS_ONLY=true
            SKIP_POLICIES=true
            SKIP_NADS=true
            shift
            ;;
        --skip-deployments)
            SKIP_DEPLOYMENTS=true
            shift
            ;;
        --skip-policies)
            SKIP_POLICIES=true
            shift
            ;;
        --skip-nads)
            SKIP_NADS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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

log_info "=========================================="
log_info "Customer-Scale Cleanup"
log_info "=========================================="
log_info "Namespace: $NAMESPACE"
if [[ "$DEPLOYMENTS_ONLY" == "true" ]]; then
    log_info "Mode: Deployments/Pods only"
else
    log_info "VLANs to delete: $VLAN_COUNT (vlan$VLAN_START-vlan$((VLAN_START + VLAN_COUNT - 1)))"
fi
log_info "Dry run: $DRY_RUN"
log_info "=========================================="
echo ""

# Check if namespace exists
if ! oc get namespace "$NAMESPACE" &>/dev/null; then
    log_warn "Namespace $NAMESPACE does not exist"
    exit 0
fi

# Count resources before deletion
if [[ "$SKIP_DEPLOYMENTS" == "false" ]]; then
    DEPLOYMENT_COUNT=$(oc get deployment -n "$NAMESPACE" -l test=customer-scale --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    POD_COUNT=$(oc get pod -n "$NAMESPACE" -l test=customer-scale --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    log_info "Found $DEPLOYMENT_COUNT deployments and $POD_COUNT pods to delete"
fi

if [[ "$SKIP_POLICIES" == "false" ]]; then
    POLICY_COUNT=$(oc get multi-networkpolicies -n "$NAMESPACE" -l test=customer-scale --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    log_info "Found $POLICY_COUNT multi-networkpolicies to delete"
fi

if [[ "$SKIP_NADS" == "false" ]]; then
    NAD_COUNT=0
    for ((v=0; v<$VLAN_COUNT; v++)); do
        VLAN_ID=$((VLAN_START + v))
        VLAN_NAME="vlan${VLAN_ID}"
        if oc get net-attach-def -n "$NAMESPACE" "$VLAN_NAME" &>/dev/null; then
            NAD_COUNT=$((NAD_COUNT + 1))
        fi
    done
    log_info "Found $NAD_COUNT network attachment definitions to delete"
fi

echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY RUN MODE - No resources will be deleted"
    echo ""

    if [[ "$SKIP_DEPLOYMENTS" == "false" && ($DEPLOYMENT_COUNT -gt 0 || $POD_COUNT -gt 0) ]]; then
        log_info "Would delete deployments and pods:"
        oc get deployment,pod -n "$NAMESPACE" -l test=customer-scale 2>/dev/null || true
        echo ""
    fi

    if [[ "$SKIP_POLICIES" == "false" && $POLICY_COUNT -gt 0 ]]; then
        log_info "Would delete multi-networkpolicies:"
        oc get multi-networkpolicies -n "$NAMESPACE" -l test=customer-scale 2>/dev/null || true
        echo ""
    fi

    if [[ "$SKIP_NADS" == "false" && $NAD_COUNT -gt 0 ]]; then
        log_info "Would delete network attachment definitions:"
        for ((v=0; v<$VLAN_COUNT; v++)); do
            VLAN_ID=$((VLAN_START + v))
            VLAN_NAME="vlan${VLAN_ID}"
            if oc get net-attach-def -n "$NAMESPACE" "$VLAN_NAME" &>/dev/null; then
                echo "  - $VLAN_NAME"
            fi
        done
        echo ""
    fi

    log_info "Dry run complete. Use without --dry-run to actually delete resources."
    exit 0
fi

# Delete deployments and pods
if [[ "$SKIP_DEPLOYMENTS" == "false" ]]; then
    log_info "Deleting deployments and pods in namespace $NAMESPACE..."

    if [[ $DEPLOYMENT_COUNT -gt 0 ]]; then
        log_info "  Deleting $DEPLOYMENT_COUNT deployments..."
        oc delete deployment -n "$NAMESPACE" -l test=customer-scale --wait=false 2>/dev/null || true
    fi

    if [[ $POD_COUNT -gt 0 ]]; then
        log_info "  Deleting $POD_COUNT standalone pods..."
        oc delete pod -n "$NAMESPACE" -l test=customer-scale --wait=false 2>/dev/null || true
    fi

    if [[ $DEPLOYMENT_COUNT -gt 0 || $POD_COUNT -gt 0 ]]; then
        log_info "  Waiting for pods to terminate..."
        oc wait pod -n "$NAMESPACE" -l test=customer-scale --for=delete --timeout=120s 2>/dev/null || log_warn "Timeout waiting for pods to terminate"
        log_info "✓ Deleted deployments and pods"
    else
        log_info "✓ No deployments or pods to delete"
    fi
    echo ""
fi

# Delete MultiNetworkPolicies
if [[ "$SKIP_POLICIES" == "false" ]]; then
    log_info "Deleting MultiNetworkPolicies in namespace $NAMESPACE..."

    if [[ $POLICY_COUNT -gt 0 ]]; then
        log_info "  Deleting $POLICY_COUNT multi-networkpolicies..."
        oc delete multi-networkpolicies -n "$NAMESPACE" -l test=customer-scale 2>/dev/null || true
        log_info "✓ Deleted $POLICY_COUNT multi-networkpolicies"
    else
        log_info "✓ No multi-networkpolicies to delete"
    fi
    echo ""
fi

# Delete NetworkAttachmentDefinitions
if [[ "$SKIP_NADS" == "false" ]]; then
    log_info "Deleting NetworkAttachmentDefinitions..."

    DELETED_NAD_COUNT=0
    for ((v=0; v<$VLAN_COUNT; v++)); do
        VLAN_ID=$((VLAN_START + v))
        VLAN_NAME="vlan${VLAN_ID}"

        if oc get net-attach-def -n "$NAMESPACE" "$VLAN_NAME" &>/dev/null; then
            log_info "  Deleting NAD: $VLAN_NAME"
            oc delete net-attach-def -n "$NAMESPACE" "$VLAN_NAME" 2>/dev/null || true
            DELETED_NAD_COUNT=$((DELETED_NAD_COUNT + 1))
        fi
    done

    if [[ $DELETED_NAD_COUNT -gt 0 ]]; then
        log_info "✓ Deleted $DELETED_NAD_COUNT network attachment definitions"
    else
        log_info "✓ No network attachment definitions to delete"
    fi
    echo ""
fi

log_info "=========================================="
log_info "Cleanup Complete"
log_info "=========================================="

# Check if namespace is now empty of customer-scale resources
REMAINING_DEPLOYMENTS=$(oc get deployment -n "$NAMESPACE" -l test=customer-scale --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
REMAINING_PODS=$(oc get pod -n "$NAMESPACE" -l test=customer-scale --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
REMAINING_POLICIES=$(oc get multi-networkpolicies -n "$NAMESPACE" -l test=customer-scale --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')

if [[ $REMAINING_DEPLOYMENTS -eq 0 && $REMAINING_PODS -eq 0 && $REMAINING_POLICIES -eq 0 ]]; then
    log_info "✓ All customer-scale resources removed from namespace $NAMESPACE"
else
    log_warn "Some resources may still remain:"
    log_warn "  Deployments: $REMAINING_DEPLOYMENTS"
    log_warn "  Pods: $REMAINING_PODS"
    log_warn "  Policies: $REMAINING_POLICIES"
    echo ""
    log_info "To check remaining resources:"
    log_info "  oc get deployment,pod,multi-networkpolicies -n $NAMESPACE -l test=customer-scale"
fi

echo ""
log_info "To verify ACL cleanup, run: ./demo-acl-check.sh"
