#!/bin/bash
#
# Generate Pods/Deployments with MultiNetworkPolicy for Layer2 Topology Testing
#
# This script creates:
# - NetworkAttachmentDefinitions (ovn-k8s-cni-overlay with layer2 topology)
# - MultiNetworkPolicy resources
# - Pods or Deployments attached to secondary networks
#

set -e

# Configuration
NAMESPACE="${NAMESPACE:-loadtest}"
TOTAL_PODS="${TOTAL_PODS:-10}"
POD_TYPE="${POD_TYPE:-deployment}"  # pod or deployment
NETWORK_COUNT="${NETWORK_COUNT:-2}"
SECURITY_GROUP_COUNT="${SECURITY_GROUP_COUNT:-5}"
OUTPUT_DIR="$(dirname "$0")/generated-pods-mnp"

# Policy configuration
FULL_SCALE_RULES="${FULL_SCALE_RULES:-false}"
PERFSONAR_FULL="${PERFSONAR_FULL:-false}"
SYNTHETIC_RULES="${SYNTHETIC_RULES:-800}"

# Network base IPs for each network
NETWORK_BASE_IPS=("192.168.100" "192.168.200")
NETWORK_NAMES=("tenant-blue" "tenant-green")

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

Generate pods/deployments with MultiNetworkPolicy using ovn-k8s-cni-overlay (layer2 topology)

OPTIONS:
    --total-pods N          Total pods to create (default: 10)
    --pod-type TYPE         Type: pod or deployment (default: deployment)
    --network-count N       Number of networks (default: 2)
    --security-groups N     Number of security groups (default: 5)
    --namespace NS          Namespace (default: loadtest)
    --output-dir DIR        Output directory (default: ./generated-pods-mnp)
    --full-scale-rules      Generate full customer-scale rules (~7,052 per pod)
    --perfsonar-full        Generate all perfSONAR ports (5000-5201, 8760-9627)
    --synthetic-rules N     Synthetic rules per direction (default: 800)
    --dry-run               Generate files without applying
    --apply                 Apply to cluster
    --clean                 Clean up resources
    -h, --help              Show this help

EXAMPLES:
    # Generate 10 deployments with simplified rules
    $0 --total-pods 10 --pod-type deployment

    # Generate with full customer-scale rules
    $0 --total-pods 10 --full-scale-rules --perfsonar-full

    # Apply to cluster
    $0 --total-pods 20 --apply

    # Clean up
    $0 --clean

EXPECTED ACL COUNT:
    Simplified (default):
      - Per pod: ~250 rules (50 allow + 200 synthetic)
      - 10 pods: ~2,500 ACLs
      - 100 pods: ~25,000 ACLs

    Full customer scale (--full-scale-rules --perfsonar-full):
      - Per pod: ~7,052 rules (5,452 allow + 1,600 synthetic)
      - 10 pods: ~70,520 ACLs
      - 100 pods: ~705,200 ACLs

EOF
}

# Parse arguments
DRY_RUN=true
APPLY=false
CLEAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --total-pods)
            TOTAL_PODS="$2"
            shift 2
            ;;
        --pod-type)
            POD_TYPE="$2"
            shift 2
            ;;
        --network-count)
            NETWORK_COUNT="$2"
            shift 2
            ;;
        --security-groups)
            SECURITY_GROUP_COUNT="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --full-scale-rules)
            FULL_SCALE_RULES=true
            PERFSONAR_FULL=true
            SYNTHETIC_RULES=800
            shift
            ;;
        --perfsonar-full)
            PERFSONAR_FULL=true
            shift
            ;;
        --synthetic-rules)
            SYNTHETIC_RULES="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            APPLY=false
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

# Cleanup function
cleanup_resources() {
    log_info "Cleaning up pods-mnp resources..."

    # Delete pods/deployments
    log_info "Deleting pods/deployments in namespace $NAMESPACE..."
    if [[ "$POD_TYPE" == "deployment" ]]; then
        oc delete deployment -n "$NAMESPACE" -l test=mnp-layer2 2>/dev/null || true
    else
        oc delete pod -n "$NAMESPACE" -l test=mnp-layer2 2>/dev/null || true
    fi

    # Delete MultiNetworkPolicies
    log_info "Deleting MultiNetworkPolicies..."
    oc delete multi-networkpolicies -n "$NAMESPACE" -l test=mnp-layer2 2>/dev/null || true

    # Delete NetworkAttachmentDefinitions
    for ((n=0; n<$NETWORK_COUNT; n++)); do
        NETWORK_NAME="${NETWORK_NAMES[$n]}"
        log_info "Deleting NAD: $NETWORK_NAME"
        oc delete net-attach-def -n "$NAMESPACE" "$NETWORK_NAME" 2>/dev/null || true
    done

    # Remove generated files
    if [[ -d "$OUTPUT_DIR" ]]; then
        log_info "Removing generated files: $OUTPUT_DIR"
        rm -rf "$OUTPUT_DIR"
    fi

    log_info "Cleanup complete"
    exit 0
}

if [[ "$CLEAN" == "true" ]]; then
    cleanup_resources
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"/{networks,pods,policies}

# Calculate distribution
PODS_PER_NETWORK=$((TOTAL_PODS / NETWORK_COUNT))
PODS_PER_SG=$((TOTAL_PODS / SECURITY_GROUP_COUNT))

log_info "=========================================="
log_info "Pods/Deployments with MultiNetworkPolicy Generator"
log_info "=========================================="
log_info "Total Pods: $TOTAL_PODS"
log_info "Pod Type: $POD_TYPE"
log_info "Networks: $NETWORK_COUNT ($PODS_PER_NETWORK pods per network)"
log_info "Security Groups: $SECURITY_GROUP_COUNT (~$PODS_PER_SG pods per SG)"
log_info "Namespace: $NAMESPACE"
log_info "Topology: layer2 (ovn-k8s-cni-overlay)"
log_info "Output: $OUTPUT_DIR"
log_info "=========================================="
echo ""

# Generate NetworkAttachmentDefinitions for each network
log_info "Generating NetworkAttachmentDefinitions for $NETWORK_COUNT networks..."
for ((n=0; n<$NETWORK_COUNT; n++)); do
    NETWORK_NAME="${NETWORK_NAMES[$n]}"
    BASE_IP="${NETWORK_BASE_IPS[$n]}"

    cat > "$OUTPUT_DIR/networks/nad-${NETWORK_NAME}.yaml" <<EOF
---
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: ${NETWORK_NAME}
  namespace: ${NAMESPACE}
spec:
  config: |
    {
      "cniVersion": "0.4.0",
      "name": "${NETWORK_NAME}-net",
      "type": "ovn-k8s-cni-overlay",
      "topology": "layer2",
      "netAttachDefName": "${NAMESPACE}/${NETWORK_NAME}",
      "subnets": "${BASE_IP}.0/24"
    }
EOF

    log_info "  Generated NAD: ${NETWORK_NAME} (${BASE_IP}.0/24, layer2 topology)"
done

# Generate Pods or Deployments
log_info "Generating $TOTAL_PODS ${POD_TYPE}s..."
for ((i=0; i<$TOTAL_PODS; i++)); do
    NETWORK_INDEX=$((i / PODS_PER_NETWORK))
    if [[ $NETWORK_INDEX -ge $NETWORK_COUNT ]]; then
        NETWORK_INDEX=$((NETWORK_COUNT - 1))
    fi

    SG_INDEX=$((i / PODS_PER_SG))
    if [[ $SG_INDEX -ge $SECURITY_GROUP_COUNT ]]; then
        SG_INDEX=$((SECURITY_GROUP_COUNT - 1))
    fi

    NETWORK_NAME="${NETWORK_NAMES[$NETWORK_INDEX]}"
    SG_NAME="sg-mnp-$((SG_INDEX + 1))"
    POD_NAME="loadtest-pod-${i}"

    if [[ "$POD_TYPE" == "deployment" ]]; then
        cat > "$OUTPUT_DIR/pods/${POD_NAME}.yaml" <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
  labels:
    security_group: ${SG_NAME}
    network: ${NETWORK_NAME}
    test: mnp-layer2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${POD_NAME}
  template:
    metadata:
      annotations:
        k8s.v1.cni.cncf.io/networks: ${NAMESPACE}/${NETWORK_NAME}
      labels:
        app: ${POD_NAME}
        security_group: ${SG_NAME}
        network: ${NETWORK_NAME}
        test: mnp-layer2
    spec:
      containers:
      - name: nginx
        image: quay.io/openshift-psap-qe/nginx-alpine:multiarch
        ports:
        - containerPort: 80
          protocol: TCP
        - containerPort: 22
          protocol: TCP
        - containerPort: 443
          protocol: TCP
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        securityContext:
          runAsNonRoot: true
          seccompProfile:
            type: RuntimeDefault
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
EOF
    else
        cat > "$OUTPUT_DIR/pods/${POD_NAME}.yaml" <<EOF
---
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
  annotations:
    k8s.v1.cni.cncf.io/networks: ${NAMESPACE}/${NETWORK_NAME}
  labels:
    app: ${POD_NAME}
    security_group: ${SG_NAME}
    network: ${NETWORK_NAME}
    test: mnp-layer2
spec:
  containers:
  - name: nginx
    image: quay.io/openshift-psap-qe/nginx-alpine:multiarch
    ports:
    - containerPort: 80
      protocol: TCP
    - containerPort: 22
      protocol: TCP
    - containerPort: 443
      protocol: TCP
    resources:
      requests:
        memory: "64Mi"
        cpu: "50m"
      limits:
        memory: "128Mi"
        cpu: "100m"
    securityContext:
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
EOF
    fi

    if [[ $((i % 10)) -eq 0 ]]; then
        echo -ne "\\r  Progress: $i/$TOTAL_PODS ${POD_TYPE}s"
    fi
done
echo ""
log_info "✓ Generated $TOTAL_PODS ${POD_TYPE} manifests"

# Generate MultiNetworkPolicies for each security group
log_info "Generating MultiNetworkPolicies for $SECURITY_GROUP_COUNT security groups..."

for ((sg=0; sg<$SECURITY_GROUP_COUNT; sg++)); do
    SG_NAME="sg-mnp-$((sg + 1))"

    # Determine which network this SG primarily uses (for annotation)
    PRIMARY_NETWORK="${NETWORK_NAMES[0]}"

    # Policy 1: Allow policy (DNS, SSH, HTTP/HTTPS, perfSONAR)
    cat > "$OUTPUT_DIR/policies/${SG_NAME}-allow-policy.yaml" <<EOF
---
apiVersion: k8s.cni.cncf.io/v1beta1
kind: MultiNetworkPolicy
metadata:
  name: ${SG_NAME}-allow
  namespace: ${NAMESPACE}
  annotations:
    k8s.v1.cni.cncf.io/policy-for: ${NAMESPACE}/${PRIMARY_NETWORK}
  labels:
    security_group: ${SG_NAME}
    policy_type: allow
    test: mnp-layer2
spec:
  podSelector:
    matchLabels:
      security_group: ${SG_NAME}
  policyTypes:
  - Ingress
  - Egress
  egress:
  # DNS
  - ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
  # SSH
  - ports:
    - port: 22
      protocol: TCP
  # HTTP/HTTPS
  - ports:
    - port: 80
      protocol: TCP
    - port: 443
      protocol: TCP
EOF

    # Add perfSONAR egress rules
    if [[ "$PERFSONAR_FULL" == "true" ]]; then
        log_info "    Generating full perfSONAR egress rules (5000-5201, 8760-9627)..."
        for port in $(seq 5000 5201); do
            cat >> "$OUTPUT_DIR/policies/${SG_NAME}-allow-policy.yaml" <<EOF
  - ports:
    - port: ${port}
      protocol: TCP
EOF
        done
        for port in $(seq 8760 9627); do
            cat >> "$OUTPUT_DIR/policies/${SG_NAME}-allow-policy.yaml" <<EOF
  - ports:
    - port: ${port}
      protocol: TCP
EOF
        done
    else
        # Simplified - representative sample
        for port in $(seq 5000 5010) $(seq 9600 9610); do
            cat >> "$OUTPUT_DIR/policies/${SG_NAME}-allow-policy.yaml" <<EOF
  - ports:
    - port: ${port}
      protocol: TCP
EOF
        done
    fi

    # Ingress rules
    cat >> "$OUTPUT_DIR/policies/${SG_NAME}-allow-policy.yaml" <<EOF
  ingress:
  # SSH
  - ports:
    - port: 22
      protocol: TCP
  # HTTP/HTTPS
  - ports:
    - port: 80
      protocol: TCP
    - port: 443
      protocol: TCP
EOF

    # Add perfSONAR ingress rules
    if [[ "$PERFSONAR_FULL" == "true" ]]; then
        log_info "    Generating full perfSONAR ingress rules (5000-5201, 8760-9627)..."
        for port in $(seq 5000 5201); do
            cat >> "$OUTPUT_DIR/policies/${SG_NAME}-allow-policy.yaml" <<EOF
  - ports:
    - port: ${port}
      protocol: TCP
EOF
        done
        for port in $(seq 8760 9627); do
            cat >> "$OUTPUT_DIR/policies/${SG_NAME}-allow-policy.yaml" <<EOF
  - ports:
    - port: ${port}
      protocol: TCP
EOF
        done
    else
        for port in $(seq 5000 5010) $(seq 9600 9610); do
            cat >> "$OUTPUT_DIR/policies/${SG_NAME}-allow-policy.yaml" <<EOF
  - ports:
    - port: ${port}
      protocol: TCP
EOF
        done
    fi

    # Policy 2: Synthetic policy (1,600 rules: 800 ingress + 800 egress)
    cat > "$OUTPUT_DIR/policies/${SG_NAME}-synthetic-policy.yaml" <<EOF
---
apiVersion: k8s.cni.cncf.io/v1beta1
kind: MultiNetworkPolicy
metadata:
  name: ${SG_NAME}-synthetic
  namespace: ${NAMESPACE}
  annotations:
    k8s.v1.cni.cncf.io/policy-for: ${NAMESPACE}/${PRIMARY_NETWORK}
  labels:
    security_group: ${SG_NAME}
    policy_type: synthetic
    test: mnp-layer2
spec:
  podSelector:
    matchLabels:
      security_group: ${SG_NAME}
  policyTypes:
  - Ingress
  - Egress
  egress:
EOF

    # Generate egress rules (customer: 800, configurable via --synthetic-rules)
    log_info "    Generating $SYNTHETIC_RULES synthetic egress rules..."
    for ((r=0; r<$SYNTHETIC_RULES; r++)); do
        IP_SUFFIX=$((10 + (r % 240)))
        PORT=$((10000 + r))
        cat >> "$OUTPUT_DIR/policies/${SG_NAME}-synthetic-policy.yaml" <<EOF
  - ports:
    - port: ${PORT}
      protocol: TCP
    to:
    - ipBlock:
        cidr: 10.0.${sg}.${IP_SUFFIX}/32
EOF
    done

    # Generate ingress rules (customer: 800, configurable via --synthetic-rules)
    log_info "    Generating $SYNTHETIC_RULES synthetic ingress rules..."
    cat >> "$OUTPUT_DIR/policies/${SG_NAME}-synthetic-policy.yaml" <<EOF
  ingress:
EOF
    for ((r=0; r<$SYNTHETIC_RULES; r++)); do
        IP_SUFFIX=$((10 + (r % 240)))
        PORT=$((10000 + r))
        cat >> "$OUTPUT_DIR/policies/${SG_NAME}-synthetic-policy.yaml" <<EOF
  - from:
    - ipBlock:
        cidr: 10.0.${sg}.${IP_SUFFIX}/32
    ports:
    - port: ${PORT}
      protocol: TCP
EOF
    done

    log_info "  Generated policies for ${SG_NAME}"
done

# Create combined manifest
log_info "Creating combined manifest..."
cat > "$OUTPUT_DIR/all-in-one.yaml" <<EOF
# Generated by: $0
# Date: $(date)
# Configuration:
#   Total Pods: $TOTAL_PODS
#   Pod Type: $POD_TYPE
#   Networks: $NETWORK_COUNT
#   Security Groups: $SECURITY_GROUP_COUNT
#   Pods per Network: $PODS_PER_NETWORK
#   Pods per SG: ~$PODS_PER_SG
#   Topology: layer2 (ovn-k8s-cni-overlay)
#
EOF

# Add NADs
cat "$OUTPUT_DIR"/networks/*.yaml >> "$OUTPUT_DIR/all-in-one.yaml"

# Add policies
cat "$OUTPUT_DIR"/policies/*.yaml >> "$OUTPUT_DIR/all-in-one.yaml"

# Add pods/deployments
cat "$OUTPUT_DIR"/pods/*.yaml >> "$OUTPUT_DIR/all-in-one.yaml"

log_info "✓ Created combined manifest: $OUTPUT_DIR/all-in-one.yaml"

# Create summary
ALLOW_RULES=$((4 + (PERFSONAR_FULL == "true" ? 2140 : 40)))
SYNTHETIC_RULES_TOTAL=$((SYNTHETIC_RULES * 2))
TOTAL_RULES_PER_POD=$((ALLOW_RULES + SYNTHETIC_RULES_TOTAL))
EXPECTED_ACLS=$((TOTAL_PODS * TOTAL_RULES_PER_POD))

cat > "$OUTPUT_DIR/SUMMARY.md" <<EOF
# Pods/Deployments with MultiNetworkPolicy Summary

**Generated**: $(date)
**Namespace**: $NAMESPACE
**Topology**: layer2 (ovn-k8s-cni-overlay)

## Configuration

| Component | Count | Details |
|-----------|-------|---------|
| **Total Pods** | $TOTAL_PODS | Type: $POD_TYPE |
| **Networks** | $NETWORK_COUNT | $PODS_PER_NETWORK pods per network |
| **Security Groups** | $SECURITY_GROUP_COUNT | ~$PODS_PER_SG pods per group |
| **Policies per SG** | 2 | Allow + Synthetic |

## Networks (Layer2 Topology)

$(for ((n=0; n<$NETWORK_COUNT; n++)); do
    echo "- **${NETWORK_NAMES[$n]}**: ${NETWORK_BASE_IPS[$n]}.0/24 (ovn-k8s-cni-overlay, layer2)"
done)

## Security Groups

$(for ((sg=0; sg<$SECURITY_GROUP_COUNT; sg++)); do
    echo "- **sg-mnp-$((sg + 1))**: ~$PODS_PER_SG pods"
done)

## Policies per Security Group

### Allow Policy
- DNS (UDP/TCP 53)
- SSH (TCP 22)
- HTTP/HTTPS (TCP 80, 443)
- perfSONAR sample (simplified from ~5,452 rules)

### Synthetic Policy
- $SYNTHETIC_RULES egress rules
- $SYNTHETIC_RULES ingress rules
- Random IPs and ports (10.0.X.X, ports 10000+)

## Expected ACL Count

**Per Pod**:
- Allow policy: ~$ALLOW_RULES rules
- Synthetic policy: $SYNTHETIC_RULES_TOTAL rules (${SYNTHETIC_RULES}×2)
- **Total per pod**: ~$TOTAL_RULES_PER_POD rules

**Total Expected ACLs**:
- This deployment: ~$EXPECTED_ACLS ACLs ($TOTAL_PODS pods × $TOTAL_RULES_PER_POD rules)
- Customer scale (1000 VMs): ~7,052,000 ACLs (1000 × 7,052 rules)

## Deployment

### Apply to Cluster
\`\`\`bash
# Create namespace
oc create namespace $NAMESPACE 2>/dev/null || true

# Apply all resources
oc apply -f $OUTPUT_DIR/all-in-one.yaml

# Or apply individually
oc apply -f $OUTPUT_DIR/networks/
oc apply -f $OUTPUT_DIR/policies/
oc apply -f $OUTPUT_DIR/pods/
\`\`\`

### Monitor
\`\`\`bash
# Watch pods/deployments
oc get pods,deployment -n $NAMESPACE -w

# Watch policies
oc get multi-networkpolicies -n $NAMESPACE

# Check NADs
oc get net-attach-def -n $NAMESPACE

# Check ACL count
cd /Users/liqcui/customer-bugs/multi-networkpolicy/loadtest
./demo-acl-check.sh
\`\`\`

### Cleanup
\`\`\`bash
$0 --clean
\`\`\`
EOF

log_info "✓ Created summary: $OUTPUT_DIR/SUMMARY.md"

echo ""
log_info "=========================================="
log_info "Generation Complete"
log_info "=========================================="
log_info "Output directory: $OUTPUT_DIR"
log_info "Files generated:"
log_info "  - Networks: $NETWORK_COUNT NADs (layer2 topology)"
log_info "  - Pods/Deployments: $TOTAL_PODS manifests"
log_info "  - Policies: $((SECURITY_GROUP_COUNT * 2)) (2 per SG)"
log_info "  - Combined: all-in-one.yaml"
echo ""
log_info "Expected ACL increase: ~$EXPECTED_ACLS ACLs"
echo ""

if [[ "$APPLY" == "true" ]]; then
    log_info "Applying to cluster..."

    # Create namespace
    oc create namespace "$NAMESPACE" 2>/dev/null || log_warn "Namespace $NAMESPACE already exists"

    # Apply NADs
    log_info "Applying NetworkAttachmentDefinitions..."
    oc apply -f "$OUTPUT_DIR/networks/"

    # Apply policies
    log_info "Applying MultiNetworkPolicies..."
    oc apply -f "$OUTPUT_DIR/policies/"

    # Apply pods/deployments
    log_info "Applying ${POD_TYPE}s..."
    oc apply -f "$OUTPUT_DIR/pods/"

    log_info "✓ Resources applied to cluster"
    log_info ""
    log_info "Monitor with:"
    log_info "  oc get pods,deployment -n $NAMESPACE -w"
    log_info "  ./demo-acl-check.sh"
else
    log_info "Dry run complete. Files generated but not applied."
    log_info ""
    log_info "To apply to cluster:"
    log_info "  $0 --apply"
    log_info ""
    log_info "To apply manually:"
    log_info "  oc create namespace $NAMESPACE"
    log_info "  oc apply -f $OUTPUT_DIR/all-in-one.yaml"
fi
