#!/bin/bash
#
# Monitor VMs and MultiNetworkPolicy status
#
# Provides real-time status of VMs and policy enforcement
#

set -e

# Configuration
NAMESPACE="${NAMESPACE:-loadtest}"
WATCH_INTERVAL="${WATCH_INTERVAL:-5}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Monitor VMs and MultiNetworkPolicy in real-time

OPTIONS:
    --namespace NS      Namespace (default: loadtest)
    --interval N        Watch interval in seconds (default: 5)
    --once              Run once and exit (no watch)
    -h, --help          Show this help

EXAMPLES:
    # Monitor with default settings
    $0

    # Monitor specific namespace
    $0 --namespace loadtest

    # Run once
    $0 --once

EOF
}

# Parse arguments
WATCH=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --interval)
            WATCH_INTERVAL="$2"
            shift 2
            ;;
        --once)
            WATCH=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check if oc is available
if ! command -v oc &> /dev/null; then
    echo "ERROR: oc command not found"
    exit 1
fi

show_status() {
    clear
    echo "========================================"
    echo "Loadtest VM Monitor - Namespace: $NAMESPACE"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================"
    echo ""

    # MultiNetworkPolicy status
    echo -e "${BLUE}[MultiNetworkPolicy]${NC}"
    if oc get multi-networkpolicies -n "$NAMESPACE" &> /dev/null; then
        oc get multi-networkpolicies -n "$NAMESPACE" 2>/dev/null || echo "No policies found"
    else
        echo "No MultiNetworkPolicy found in namespace $NAMESPACE"
    fi
    echo ""

    # VM status
    echo -e "${BLUE}[VirtualMachines]${NC}"
    if oc get vm -n "$NAMESPACE" &> /dev/null; then
        oc get vm -n "$NAMESPACE" 2>/dev/null | head -20 || echo "No VMs found"
    else
        echo "No VMs found in namespace $NAMESPACE"
    fi
    echo ""

    # VMI status
    echo -e "${BLUE}[VirtualMachineInstances]${NC}"
    if oc get vmi -n "$NAMESPACE" &> /dev/null; then
        oc get vmi -n "$NAMESPACE" 2>/dev/null | head -20 || echo "No VMIs found"
    else
        echo "No VMIs found"
    fi
    echo ""

    # Summary
    VM_COUNT=$(oc get vm -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    VMI_COUNT=$(oc get vmi -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    RUNNING_COUNT=$(oc get vm -n "$NAMESPACE" -o json 2>/dev/null | jq -r '.items[] | select(.status.printableStatus == "Running") | .metadata.name' | wc -l)
    POLICY_COUNT=$(oc get multi-networkpolicies -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)

    echo -e "${BLUE}[Summary]${NC}"
    echo "  VMs defined: $VM_COUNT"
    echo "  VMs running: $RUNNING_COUNT"
    echo "  VMIs active: $VMI_COUNT"
    echo "  Policies: $POLICY_COUNT"
    echo ""

    # Recent events
    echo -e "${BLUE}[Recent Events]${NC}"
    oc get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -10 || echo "No recent events"
    echo ""

    if [[ "$WATCH" == "true" ]]; then
        echo "Press Ctrl+C to exit. Refreshing every ${WATCH_INTERVAL}s..."
    fi
}

if [[ "$WATCH" == "true" ]]; then
    # Watch mode
    while true; do
        show_status
        sleep "$WATCH_INTERVAL"
    done
else
    # Run once
    show_status
fi
