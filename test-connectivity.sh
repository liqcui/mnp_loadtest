#!/bin/bash
#
# Test connectivity between VMs to verify MultiNetworkPolicy
#
# This script tests both allowed and blocked connections
# to verify that MultiNetworkPolicy is working correctly
#

set -e

# Configuration
NAMESPACE="${NAMESPACE:-loadtest}"
VM_COUNT="${VM_COUNT:-10}"
BASE_IP="${BASE_IP:-192.168.10}"
START_IP="${START_IP:-10}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Test connectivity between VMs to verify MultiNetworkPolicy enforcement

OPTIONS:
    --namespace NS      Namespace (default: loadtest)
    --vm-count N        Number of VMs (default: 10)
    --base-ip X.X.X     Base IP (default: 192.168.10)
    --start-ip N        Starting IP suffix (default: 10)
    --vm-name NAME      Test specific VM (default: loadtest-vm-0)
    --quick             Quick test (fewer checks)
    -h, --help          Show this help

EXAMPLES:
    # Test from first VM
    $0

    # Test specific VM
    $0 --vm-name loadtest-vm-5

    # Quick test
    $0 --quick

EOF
}

# Parse arguments
VM_NAME="loadtest-vm-0"
QUICK=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --vm-count)
            VM_COUNT="$2"
            shift 2
            ;;
        --base-ip)
            BASE_IP="$2"
            shift 2
            ;;
        --start-ip)
            START_IP="$2"
            shift 2
            ;;
        --vm-name)
            VM_NAME="$2"
            shift 2
            ;;
        --quick)
            QUICK=true
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
    log_fail "oc command not found. Please install OpenShift CLI."
    exit 1
fi

# Check if virtctl is available
if ! command -v virtctl &> /dev/null; then
    log_fail "virtctl command not found. Install from: https://github.com/kubevirt/kubevirt/releases"
    exit 1
fi

log_info "Testing connectivity for VMs in namespace: $NAMESPACE"
log_info "Test VM: $VM_NAME"
echo ""

# Check if VM exists
if ! oc get vm "$VM_NAME" -n "$NAMESPACE" &> /dev/null; then
    log_fail "VM $VM_NAME not found in namespace $NAMESPACE"
    exit 1
fi

# Check if VM is running
VM_RUNNING=$(oc get vm "$VM_NAME" -n "$NAMESPACE" -o jsonpath='{.status.printableStatus}')
if [[ "$VM_RUNNING" != "Running" ]]; then
    log_fail "VM $VM_NAME is not running (status: $VM_RUNNING)"
    exit 1
fi

log_pass "VM $VM_NAME is running"

# Get VM pod name
VMI_POD=$(oc get pods -n "$NAMESPACE" -l kubevirt.io/vm="$VM_NAME" -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$VMI_POD" ]]; then
    log_fail "Could not find pod for VM $VM_NAME"
    exit 1
fi

log_info "VM pod: $VMI_POD"
echo ""

# Function to run command in VM
vm_exec() {
    local cmd="$1"
    oc exec -n "$NAMESPACE" "$VMI_POD" -- bash -c "$cmd" 2>/dev/null
}

# Test 1: Check network interfaces
log_test "Test 1: Checking network interfaces"
INTERFACES=$(vm_exec "ip -br addr show" || echo "")
if [[ -z "$INTERFACES" ]]; then
    log_fail "Could not get network interfaces"
else
    echo "$INTERFACES"
    log_pass "Network interfaces detected"
fi
echo ""

# Test 2: Test allowed egress connections
log_test "Test 2: Testing allowed egress connections"
PASS_COUNT=0
FAIL_COUNT=0

if [[ "$QUICK" == "true" ]]; then
    TEST_COUNT=3
else
    TEST_COUNT=$((VM_COUNT > 5 ? 5 : VM_COUNT))
fi

for i in $(seq 0 $((TEST_COUNT - 1))); do
    TARGET_IP="$BASE_IP.$((START_IP + i))"
    TARGET_PORT=$((3306 + i))

    log_info "Testing connection to $TARGET_IP:$TARGET_PORT (allowed)"

    # Use timeout to avoid hanging
    if vm_exec "timeout 3 nc -zv $TARGET_IP $TARGET_PORT 2>&1" | grep -q "succeeded\|open"; then
        log_pass "  Connection to $TARGET_IP:$TARGET_PORT succeeded (expected)"
        ((PASS_COUNT++))
    else
        log_fail "  Connection to $TARGET_IP:$TARGET_PORT failed (unexpected)"
        ((FAIL_COUNT++))
    fi
done

echo ""
log_info "Allowed connections: $PASS_COUNT passed, $FAIL_COUNT failed"
echo ""

# Test 3: Test blocked egress connections
log_test "Test 3: Testing blocked egress connections"
PASS_COUNT=0
FAIL_COUNT=0

# Test connections that should be blocked
BLOCKED_TESTS=(
    "8.8.8.8:53:DNS to Google (should be blocked)"
    "1.1.1.1:443:HTTPS to Cloudflare (should be blocked)"
    "$BASE_IP.$((START_IP + 1)):9999:Random port (should be blocked)"
)

for test in "${BLOCKED_TESTS[@]}"; do
    IFS=':' read -r ip port desc <<< "$test"

    log_info "Testing connection to $ip:$port - $desc"

    # Use timeout and expect failure
    if vm_exec "timeout 3 nc -zv $ip $port 2>&1" | grep -q "succeeded\|open"; then
        log_fail "  Connection to $ip:$port succeeded (unexpected - should be blocked)"
        ((FAIL_COUNT++))
    else
        log_pass "  Connection to $ip:$port blocked (expected)"
        ((PASS_COUNT++))
    fi
done

echo ""
log_info "Blocked connections: $PASS_COUNT blocked correctly, $FAIL_COUNT incorrectly allowed"
echo ""

# Test 4: Check DNS resolution
log_test "Test 4: Testing DNS resolution"
if vm_exec "nslookup kubernetes.default.svc.cluster.local 2>&1" | grep -q "Address"; then
    log_pass "DNS resolution working"
else
    log_fail "DNS resolution failed"
fi
echo ""

# Test 5: Check pod network connectivity (should work - not affected by MultiNetworkPolicy)
log_test "Test 5: Testing pod network connectivity"
if vm_exec "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 https://kubernetes.default.svc 2>&1" | grep -q "200\|401\|403"; then
    log_pass "Pod network connectivity working"
else
    log_fail "Pod network connectivity failed"
fi
echo ""

# Summary
echo "========================================"
log_info "Test Summary"
echo "========================================"
log_info "VM: $VM_NAME"
log_info "Namespace: $NAMESPACE"
log_info "Note: MultiNetworkPolicy only affects secondary network (net1)"
log_info "      Pod network (eth0) is not affected by MultiNetworkPolicy"
echo ""
log_info "Next steps:"
echo "  1. Console into VM: virtctl console $VM_NAME -n $NAMESPACE"
echo "  2. Check interfaces: ip addr show"
echo "  3. Monitor traffic: tcpdump -i net1 -n"
echo "  4. Test manually: nc -zv <ip> <port>"
