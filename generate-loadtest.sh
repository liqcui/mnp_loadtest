#!/bin/bash
#
# Loadtest Simulation Generator
# Generates VMs and MultiNetworkPolicy for testing
#
# Based on customer's configuration:
# - Network: ovs-bridge-vlan204
# - Security group: sg-loadtest-1
# - Complex ingress/egress rules
#

set -e

# Configuration
NAMESPACE="${NAMESPACE:-loadtest}"
NETWORK_NAMESPACE="${NETWORK_NAMESPACE:-default}"
NETWORK_NAME="${NETWORK_NAME:-ovs-bridge-vlan204}"
SECURITY_GROUP="${SECURITY_GROUP:-sg-loadtest-1}"
VM_COUNT="${VM_COUNT:-10}"
RULES_PER_VM="${RULES_PER_VM:-10}"  # Egress + Ingress rules per VM
OUTPUT_DIR="$(dirname "$0")/generated"

# VM Resources
CPU_CORES="${CPU_CORES:-1}"
CPU_SOCKETS="${CPU_SOCKETS:-1}"
MEMORY="${MEMORY:-512Mi}"
STORAGE="${STORAGE:-10Gi}"

# Network configuration
BASE_IP="${BASE_IP:-192.168.10}"
START_IP="${START_IP:-10}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
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

Generate loadtest VMs and MultiNetworkPolicy for testing

OPTIONS:
    --namespace NS              Namespace for VMs (default: loadtest)
    --network-namespace NS      Namespace of NetworkAttachmentDefinition (default: default)
    --network-name NAME         NetworkAttachmentDefinition name (default: ovs-bridge-vlan204)
    --security-group NAME       Security group label (default: sg-loadtest-1)
    --vm-count N                Number of VMs to generate (default: 10)
    --rules-per-vm N            Egress+Ingress rules per VM (default: 10)
    --base-ip X.X.X             Base IP for network (default: 192.168.10)
    --start-ip N                Starting IP suffix (default: 10)
    --cpu-cores N               CPU cores per VM (default: 1)
    --cpu-sockets N             CPU sockets per VM (default: 2)
    --memory SIZE               Memory per VM (default: 2Gi)
    --storage SIZE              Storage per VM (default: 30Gi)
    --output-dir DIR            Output directory (default: ./generated)
    --dry-run                   Generate files without applying
    --apply                     Apply generated manifests to cluster
    --clean                     Remove generated files and resources
    -h, --help                  Show this help message

EXAMPLES:
    # Generate 10 VMs with 10 rules each (default)
    $0

    # Generate 50 VMs with 20 rules per VM
    $0 --vm-count 50 --rules-per-vm 20

    # Generate and apply to cluster
    $0 --vm-count 10 --apply

    # Custom network configuration
    $0 --namespace loadtest \\
       --network-namespace loadtest \\
       --network-name vlan750-loadtest-vm-10-234-111-0-24 \\
       --base-ip 10.234.111

    # Clean up resources
    $0 --clean

EOF
}

# Parse arguments
DRY_RUN=true
APPLY=false
CLEAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --network-namespace)
            NETWORK_NAMESPACE="$2"
            shift 2
            ;;
        --network-name)
            NETWORK_NAME="$2"
            shift 2
            ;;
        --security-group)
            SECURITY_GROUP="$2"
            shift 2
            ;;
        --vm-count)
            VM_COUNT="$2"
            shift 2
            ;;
        --rules-per-vm)
            RULES_PER_VM="$2"
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
        --cpu-cores)
            CPU_CORES="$2"
            shift 2
            ;;
        --cpu-sockets)
            CPU_SOCKETS="$2"
            shift 2
            ;;
        --memory)
            MEMORY="$2"
            shift 2
            ;;
        --storage)
            STORAGE="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --apply)
            APPLY=true
            DRY_RUN=false
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

# Clean up function
cleanup() {
    if [[ "$CLEAN" == "true" ]]; then
        log_info "Cleaning up resources..."

        if [[ -d "$OUTPUT_DIR" ]]; then
            log_info "Removing generated files in $OUTPUT_DIR"
            rm -rf "$OUTPUT_DIR"
        fi

        if command -v oc &> /dev/null; then
            log_info "Deleting VMs in namespace $NAMESPACE"
            oc delete vm -n "$NAMESPACE" -l security_group="$SECURITY_GROUP" --ignore-not-found=true

            log_info "Deleting MultiNetworkPolicy in namespace $NAMESPACE"
            oc delete multinetworkpolicy -n "$NAMESPACE" -l access-policy="$SECURITY_GROUP" --ignore-not-found=true
        fi

        log_info "Cleanup complete"
        exit 0
    fi
}

cleanup

# Create output directory
mkdir -p "$OUTPUT_DIR/vms"
mkdir -p "$OUTPUT_DIR/policy"

log_info "Generating loadtest configuration..."
log_info "  Namespace: $NAMESPACE"
log_info "  Network: $NETWORK_NAMESPACE/$NETWORK_NAME"
log_info "  Security Group: $SECURITY_GROUP"
log_info "  VM Count: $VM_COUNT"
log_info "  Rules per VM: $RULES_PER_VM (total: $((RULES_PER_VM * 2)))"
log_info "  Output: $OUTPUT_DIR"
echo ""

# Generate VMs
log_info "Generating $VM_COUNT VMs..."

for i in $(seq 0 $((VM_COUNT - 1))); do
    VM_NAME="loadtest-vm-${i}"
    VM_IP="$BASE_IP.$((START_IP + i))"

    cat > "$OUTPUT_DIR/vms/${VM_NAME}.yaml" <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${VM_NAME}
  namespace: ${NAMESPACE}
  labels:
    security_group: ${SECURITY_GROUP}
    kubevirt.io/vm: ${VM_NAME}
    loadtest-vm-id: "${i}"
spec:
  running: true
  template:
    metadata:
      labels:
        security_group: ${SECURITY_GROUP}
        kubevirt.io/vm: ${VM_NAME}
        loadtest-vm-id: "${i}"
    spec:
      domain:
        cpu:
          cores: ${CPU_CORES}
          sockets: ${CPU_SOCKETS}
          threads: 1
        devices:
          disks:
          - disk:
              bus: virtio
            name: rootdisk
          - disk:
              bus: virtio
            name: cloudinitdisk
          interfaces:
          - name: default
            masquerade: {}
          - name: secondary
            bridge: {}
        memory:
          guest: ${MEMORY}
        resources:
          requests:
            memory: ${MEMORY}
      networks:
      - name: default
        pod: {}
      - name: secondary
        multus:
          networkName: ${NETWORK_NAME}
      terminationGracePeriodSeconds: 0
      volumes:
      - containerDisk:
          image: quay.io/containerdisks/centos-stream:9
        name: rootdisk
      - cloudInitNoCloud:
          userData: |
            #cloud-config
            user: cloud-user
            password: changeme
            chpasswd:
              expire: false
            packages:
              - vim
              - net-tools
              - bind-utils
              - curl
              - wget
              - iperf3
              - tcpdump
              - nmap
            runcmd:
              - echo "Loadtest VM ${i} - IP: ${VM_IP}" > /etc/motd
              - systemctl enable --now sshd
        name: cloudinitdisk
EOF

    log_info "  Created: $OUTPUT_DIR/vms/${VM_NAME}.yaml"
done

echo ""
log_info "Generating MultiNetworkPolicy with $((RULES_PER_VM * 2)) rules ($RULES_PER_VM egress + $RULES_PER_VM ingress)..."

# Generate MultiNetworkPolicy
cat > "$OUTPUT_DIR/policy/multinetworkpolicy.yaml" <<EOF
apiVersion: k8s.cni.cncf.io/v1beta1
kind: MultiNetworkPolicy
metadata:
  annotations:
    k8s.v1.cni.cncf.io/policy-for: ${NETWORK_NAMESPACE}/${NETWORK_NAME}
  labels:
    access-policy: ${SECURITY_GROUP}
  name: ${SECURITY_GROUP}
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      security_group: ${SECURITY_GROUP}
  policyTypes:
  - Ingress
  - Egress
  egress:
EOF

# Generate egress rules
for i in $(seq 0 $((RULES_PER_VM - 1))); do
    TARGET_IP="$BASE_IP.$((START_IP + i))"
    PORT=$((3306 + i))

    cat >> "$OUTPUT_DIR/policy/multinetworkpolicy.yaml" <<EOF
  - ports:
    - port: "${PORT}"
      protocol: TCP
    to:
    - ipBlock:
        cidr: ${TARGET_IP}/32
EOF
done

# Add ingress rules
cat >> "$OUTPUT_DIR/policy/multinetworkpolicy.yaml" <<EOF
  ingress:
EOF

for i in $(seq 0 $((RULES_PER_VM - 1))); do
    SOURCE_IP="$BASE_IP.$((START_IP + i))"
    PORT=$((3306 + i))

    cat >> "$OUTPUT_DIR/policy/multinetworkpolicy.yaml" <<EOF
  - from:
    - ipBlock:
        cidr: ${SOURCE_IP}/32
    ports:
    - port: "${PORT}"
      protocol: TCP
EOF
done

log_info "  Created: $OUTPUT_DIR/policy/multinetworkpolicy.yaml"

# Generate all-in-one manifest
echo ""
log_info "Generating all-in-one manifest..."

cat > "$OUTPUT_DIR/all-in-one.yaml" <<EOF
# Generated by: $0
# Date: $(date)
# Configuration:
#   Namespace: ${NAMESPACE}
#   Network: ${NETWORK_NAMESPACE}/${NETWORK_NAME}
#   Security Group: ${SECURITY_GROUP}
#   VM Count: ${VM_COUNT}
#   Rules: ${RULES_PER_VM} egress + ${RULES_PER_VM} ingress
#
---
EOF

cat "$OUTPUT_DIR/policy/multinetworkpolicy.yaml" >> "$OUTPUT_DIR/all-in-one.yaml"

for i in $(seq 0 $((VM_COUNT - 1))); do
    echo "---" >> "$OUTPUT_DIR/all-in-one.yaml"
    cat "$OUTPUT_DIR/vms/loadtest-vm-${i}.yaml" >> "$OUTPUT_DIR/all-in-one.yaml"
done

log_info "  Created: $OUTPUT_DIR/all-in-one.yaml"

# Generate summary
# Build VM file list
VM_FILE_LIST=""
for i in $(seq 0 $((VM_COUNT - 1))); do
    VM_FILE_LIST="${VM_FILE_LIST}│   ├── loadtest-vm-${i}.yaml
"
done

# Build IP mapping
IP_MAPPING=""
for i in $(seq 0 $((VM_COUNT - 1))); do
    IP_MAPPING="${IP_MAPPING}| loadtest-vm-${i} | ${BASE_IP}.$((START_IP + i)) |
"
done

# Build egress rules
EGRESS_RULES=""
for i in $(seq 0 $((RULES_PER_VM - 1))); do
    EGRESS_RULES="${EGRESS_RULES}- Allow TCP:$((3306 + i)) to ${BASE_IP}.$((START_IP + i))/32
"
done

# Build ingress rules
INGRESS_RULES=""
for i in $(seq 0 $((RULES_PER_VM - 1))); do
    INGRESS_RULES="${INGRESS_RULES}- Allow TCP:$((3306 + i)) from ${BASE_IP}.$((START_IP + i))/32
"
done

cat > "$OUTPUT_DIR/SUMMARY.md" <<EOF
# Loadtest Configuration Summary

**Generated**: $(date)

## Configuration

| Parameter | Value |
|-----------|-------|
| Namespace | \`${NAMESPACE}\` |
| Network Namespace | \`${NETWORK_NAMESPACE}\` |
| Network Attachment | \`${NETWORK_NAME}\` |
| Security Group | \`${SECURITY_GROUP}\` |
| VM Count | ${VM_COUNT} |
| Egress Rules | ${RULES_PER_VM} |
| Ingress Rules | ${RULES_PER_VM} |
| **Total Rules** | **$((RULES_PER_VM * 2))** |

## Resources

| Resource | Value |
|----------|-------|
| CPU | ${CPU_SOCKETS} sockets × ${CPU_CORES} cores |
| Memory | ${MEMORY} |
| Storage | ${STORAGE} |

## Generated Files

\`\`\`
${OUTPUT_DIR}/
├── vms/
${VM_FILE_LIST}├── policy/
│   └── multinetworkpolicy.yaml
├── all-in-one.yaml
└── SUMMARY.md
\`\`\`

## Deployment

### Option 1: Deploy All at Once
\`\`\`bash
oc apply -f ${OUTPUT_DIR}/all-in-one.yaml
\`\`\`

### Option 2: Deploy Step by Step
\`\`\`bash
# 1. Create namespace (if not exists)
oc create namespace ${NAMESPACE} --dry-run=client -o yaml | oc apply -f -

# 2. Apply MultiNetworkPolicy first
oc apply -f ${OUTPUT_DIR}/policy/multinetworkpolicy.yaml

# 3. Apply VMs
oc apply -f ${OUTPUT_DIR}/vms/
\`\`\`

## Verification

\`\`\`bash
# Check MultiNetworkPolicy
oc get multinetworkpolicy -n ${NAMESPACE}

# Check VMs
oc get vm -n ${NAMESPACE}

# Check running instances
oc get vmi -n ${NAMESPACE}

# Check pods with security group label
oc get pods -n ${NAMESPACE} -l security_group=${SECURITY_GROUP} --show-labels
\`\`\`

## Testing

### Test Connectivity Between VMs

\`\`\`bash
# Console into first VM
virtctl console loadtest-vm-0 -n ${NAMESPACE}

# Inside VM, test allowed connections (should work)
curl ${BASE_IP}.$((START_IP + 1)):3307
nc -zv ${BASE_IP}.$((START_IP + 2)) 3308

# Test blocked connections (should timeout)
curl ${BASE_IP}.$((START_IP + 1)):9999
nc -zv 8.8.8.8 53
\`\`\`

### Monitor Traffic

\`\`\`bash
# Inside VM, capture on secondary interface
sudo tcpdump -i net1 -n -v
\`\`\`

## Cleanup

\`\`\`bash
# Delete all resources
oc delete -f ${OUTPUT_DIR}/all-in-one.yaml

# Or delete by label
oc delete vm -n ${NAMESPACE} -l security_group=${SECURITY_GROUP}
oc delete multinetworkpolicy -n ${NAMESPACE} -l access-policy=${SECURITY_GROUP}
\`\`\`

## IP Address Mapping

| VM Name | Expected IP |
|---------|-------------|
${IP_MAPPING}

## Rule Details

### Egress Rules (VM → External)
${EGRESS_RULES}

### Ingress Rules (External → VM)
${INGRESS_RULES}

EOF

log_info "  Created: $OUTPUT_DIR/SUMMARY.md"

echo ""
log_info "Generation complete!"
echo ""
log_info "Summary:"
log_info "  VMs: $VM_COUNT"
log_info "  MultiNetworkPolicy rules: $((RULES_PER_VM * 2))"
log_info "  Output directory: $OUTPUT_DIR"
echo ""

if [[ "$APPLY" == "true" ]]; then
    log_info "Applying to cluster..."

    # Check if oc is available
    if ! command -v oc &> /dev/null; then
        log_error "oc command not found. Please install OpenShift CLI."
        exit 1
    fi

    # Create namespace if not exists
    log_info "Creating namespace $NAMESPACE (if not exists)..."
    oc create namespace "$NAMESPACE" --dry-run=client -o yaml | oc apply -f -

    # Apply policy first
    log_info "Applying MultiNetworkPolicy..."
    oc apply -f "$OUTPUT_DIR/policy/multinetworkpolicy.yaml"

    # Apply VMs
    log_info "Applying VMs..."
    oc apply -f "$OUTPUT_DIR/vms/"

    echo ""
    log_info "Deployment complete!"
    log_info "Check status with:"
    echo "  oc get vm -n $NAMESPACE"
    echo "  oc get vmi -n $NAMESPACE"
    echo "  oc get multinetworkpolicy -n $NAMESPACE"
else
    log_info "Next steps:"
    echo "  1. Review generated files in: $OUTPUT_DIR"
    echo "  2. Deploy with: oc apply -f $OUTPUT_DIR/all-in-one.yaml"
    echo "  3. Or use: $0 --apply"
fi

echo ""
log_info "View summary: cat $OUTPUT_DIR/SUMMARY.md"
