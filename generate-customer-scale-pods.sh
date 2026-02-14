#!/bin/bash
#
# Generate Customer-Scale MultiNetworkPolicy Deployment (Pods/Deployments)
#
# Mimics customer's actual environment:
# - 485 MultiNetworkPolicies (CIDR-heavy, not port-heavy)
# - 1,000 Pods/Deployments across 9 VLANs
# - Target: 3,745,000 ACLs (3,745 per pod)
# - Few ports (~2) × Many CIDRs (~450) per policy
#

set -e

# Configuration
NAMESPACE="${NAMESPACE:-loadtest}"
DEPLOYMENT_COUNT="${DEPLOYMENT_COUNT:-100}"     # Number of deployments to create
REPLICAS_PER_DEPLOYMENT="${REPLICAS_PER_DEPLOYMENT:-1}"  # Replicas per deployment
TOTAL_PODS="${TOTAL_PODS:-}"                    # Auto-calculated if not set
POD_TYPE="${POD_TYPE:-deployment}"              # deployment or pod
VLAN_COUNT="${VLAN_COUNT:-9}"
POLICY_COUNT="${POLICY_COUNT:-485}"
SLEEP_INTERVAL="${SLEEP_INTERVAL:-10}"          # Sleep seconds between deployments
OUTPUT_DIR="$(dirname "$0")/generated-customer-scale-pods"

# Policy configuration - matching customer pattern
PORTS_PER_POLICY="${PORTS_PER_POLICY:-2}"      # Customer avg: ~1.75
CIDRS_PER_POLICY="${CIDRS_PER_POLICY:-450}"     # Customer avg: ~450
POLICIES_PER_VM="${POLICIES_PER_VM:-50}"        # To reach 3,745 ACLs per VM

# VLAN base configuration (matching customer vlan750-758)
VLAN_START=750
VLAN_BASE_IP="10.234"

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

# Function to check and enable MultiNetworkPolicy support
enable_multinetworkpolicy() {
    log_info "Checking MultiNetworkPolicy support..."

    # Check if useMultiNetworkPolicy is already enabled
    MNP_ENABLED=$(oc get network.operator.openshift.io cluster -o jsonpath='{.spec.useMultiNetworkPolicy}' 2>/dev/null || echo "false")

    if [[ "$MNP_ENABLED" == "true" ]]; then
        log_info "✓ MultiNetworkPolicy is already enabled"
        return 0
    fi

    log_warn "MultiNetworkPolicy is not enabled. Enabling now..."

    # Enable MultiNetworkPolicy
    oc patch network.operator.openshift.io cluster --type=merge -p '{"spec":{"useMultiNetworkPolicy":true}}'

    if [[ $? -ne 0 ]]; then
        log_error "Failed to enable MultiNetworkPolicy"
        return 1
    fi

    log_info "✓ MultiNetworkPolicy enabled successfully"

    # Sleep 20 seconds to allow the system to process the configuration change
    log_info "Waiting 20 seconds for system to process the configuration change..."
    sleep 20

    log_info "Waiting for ovnkube-node DaemonSet rollout..."

    # Sleep 15 seconds before checking rollout to allow Kubernetes to start the update
    log_info "Waiting 15 seconds for rollout to start..."
    sleep 15

    # Wait for DaemonSet rollout to complete (max 10 minutes)
    log_info "Waiting for ovnkube-node DaemonSet rollout to complete..."
    if ! oc -n openshift-ovn-kubernetes rollout status daemonset/ovnkube-node --timeout=600s 2>&1; then
        log_error "Timeout waiting for ovnkube-node DaemonSet rollout"
        log_warn "Current status:"
        oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-node
        return 1
    fi

    log_info "✓ ovnkube-node DaemonSet rollout completed"

    # Additional verification: Wait for ALL pods to be truly ready
    log_info "Verifying all ovnkube-node pods are ready..."
    MAX_RETRIES=30
    RETRY_COUNT=0

    while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
        READY_COUNT=$(oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-node -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True" || echo "0")
        TOTAL_COUNT=$(oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-node --no-headers 2>/dev/null | wc -l)

        # Trim whitespace
        READY_COUNT=$(echo "$READY_COUNT" | tr -d '[:space:]')
        TOTAL_COUNT=$(echo "$TOTAL_COUNT" | tr -d '[:space:]')

        if [[ "$READY_COUNT" == "$TOTAL_COUNT" ]] && [[ "$TOTAL_COUNT" -gt 0 ]]; then
            log_info "✓ All $READY_COUNT/$TOTAL_COUNT ovnkube-node pods are ready"

            # Extra verification: Check for any pods in non-Running state
            NON_RUNNING=$(oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-node -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -v "Running" | wc -l | tr -d '[:space:]')

            if [[ "$NON_RUNNING" -eq 0 ]]; then
                log_info "✓ All ovnkube-node pods are in Running state"
                return 0
            else
                log_warn "Found $NON_RUNNING pods not in Running state, waiting..."
            fi
        else
            log_info "Waiting for all pods to be ready... ($READY_COUNT/$TOTAL_COUNT ready)"
        fi

        RETRY_COUNT=$((RETRY_COUNT + 1))
        sleep 10
    done

    # If we get here, not all pods became ready in time
    log_error "Not all ovnkube-node pods became ready after $((MAX_RETRIES * 10)) seconds"
    log_error "Ready pods: $READY_COUNT/$TOTAL_COUNT"
    log_warn "Current pod status:"
    oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-node
    return 1
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Generate customer-scale MultiNetworkPolicy deployment matching real environment:
- CIDR-heavy policies (few ports, many CIDR blocks)
- Multi-VLAN policies (policies apply across multiple VLANs)
- Target: 3,745 ACLs per Pod

OPTIONS:
    --deployment-count N     Number of deployments to create (default: 100)
    --replicas N            Replicas per deployment (default: 1)
    --total-pods N          Total Pods (overrides deployment-count × replicas calculation)
    --pod-type TYPE         Pod type: pod or deployment (default: deployment)
    --vlan-count N          Number of VLANs (default: 9, matching customer)
    --policy-count N        Number of policies to generate (default: 485)
    --cidrs-per-policy N    CIDR blocks per policy (default: 450)
    --sleep-interval N      Sleep seconds between deployments (default: 10)
    --namespace NS          Namespace (default: loadtest)
    --output-dir DIR        Output directory (default: ./generated-customer-scale-pods)
    --dry-run               Generate files without applying
    --apply                 Apply to cluster
    --clean                 Clean up resources
    -h, --help              Show this help

EXAMPLES:
    # Default: 100 deployments with 1 replica each (100 pods total)
    $0 --apply

    # 50 deployments with 2 replicas each (100 pods total)
    $0 --deployment-count 50 --replicas 2 --apply

    # 10 deployments with 1 replica, 5 policies
    $0 --deployment-count 10 --replicas 1 --policy-count 5 --apply

    # Full scale: 100 deployments with 10 replicas (1000 pods)
    $0 --deployment-count 100 --replicas 10 --policy-count 485 --apply

    # Custom sleep interval (5 seconds)
    $0 --deployment-count 20 --sleep-interval 5 --apply

    # Clean up
    $0 --clean

EXPECTED ACL COUNT:
    Formula: Pods × CIDRS_PER_POLICY × PORTS_PER_POLICY × (POLICY_COUNT / Pods)

    Default (100 Pods, 485 policies):     ~374,500 ACLs
    Medium (500 Pods, 485 policies):      ~1,872,500 ACLs
    Full (1000 Pods, 485 policies):       ~3,745,000 ACLs

EOF
}

# Parse arguments
DRY_RUN=true
APPLY=false
CLEAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --deployment-count)
            DEPLOYMENT_COUNT="$2"
            shift 2
            ;;
        --replicas)
            REPLICAS_PER_DEPLOYMENT="$2"
            shift 2
            ;;
        --total-pods)
            TOTAL_PODS="$2"
            shift 2
            ;;
        --vlan-count)
            VLAN_COUNT="$2"
            shift 2
            ;;
        --policy-count)
            POLICY_COUNT="$2"
            shift 2
            ;;
        --cidrs-per-policy)
            CIDRS_PER_POLICY="$2"
            shift 2
            ;;
        --sleep-interval)
            SLEEP_INTERVAL="$2"
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
    log_info "Cleaning up customer-scale resources..."

    # Delete pods/deployments
    log_info "Deleting pods/deployments in namespace $NAMESPACE..."
    oc delete deployment -n "$NAMESPACE" -l test=customer-scale 2>/dev/null || true
    oc delete pod -n "$NAMESPACE" -l test=customer-scale 2>/dev/null || true

    # Delete MultiNetworkPolicies
    log_info "Deleting MultiNetworkPolicies..."
    oc delete multi-networkpolicies -n "$NAMESPACE" -l test=customer-scale 2>/dev/null || true

    # Delete NetworkAttachmentDefinitions
    for ((v=0; v<$VLAN_COUNT; v++)); do
        VLAN_ID=$((VLAN_START + v))
        VLAN_NAME="vlan${VLAN_ID}"
        log_info "Deleting NAD: $VLAN_NAME"
        oc delete net-attach-def -n "$NAMESPACE" "$VLAN_NAME" 2>/dev/null || true
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

# Clean up old generated files if they exist
if [[ -d "$OUTPUT_DIR" ]]; then
    log_info "Cleaning up old generated files: $OUTPUT_DIR"
    rm -rf "$OUTPUT_DIR"
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"/{networks,pods,policies}

# Calculate TOTAL_PODS if not explicitly set
if [[ -z "$TOTAL_PODS" ]]; then
    TOTAL_PODS=$((DEPLOYMENT_COUNT * REPLICAS_PER_DEPLOYMENT))
else
    # If TOTAL_PODS is set, recalculate DEPLOYMENT_COUNT and REPLICAS_PER_DEPLOYMENT
    # Keep REPLICAS_PER_DEPLOYMENT, adjust DEPLOYMENT_COUNT
    DEPLOYMENT_COUNT=$((TOTAL_PODS / REPLICAS_PER_DEPLOYMENT))
    if [[ $DEPLOYMENT_COUNT -eq 0 ]]; then
        DEPLOYMENT_COUNT=1
    fi
fi

# Calculate distribution
PODS_PER_VLAN=$((TOTAL_PODS / VLAN_COUNT))
if [[ $PODS_PER_VLAN -eq 0 && $TOTAL_PODS -gt 0 ]]; then
    PODS_PER_VLAN=1
fi

# Calculate expected ACLs
if [[ $TOTAL_PODS -gt 0 ]]; then
    EXPECTED_ACLS_PER_POD=$((CIDRS_PER_POLICY * PORTS_PER_POLICY * POLICY_COUNT / TOTAL_PODS))
    TOTAL_EXPECTED_ACLS=$((EXPECTED_ACLS_PER_POD * TOTAL_PODS))
else
    EXPECTED_ACLS_PER_POD=0
    TOTAL_EXPECTED_ACLS=0
fi

log_info "=========================================="
log_info "Customer-Scale MNP Generator"
log_info "=========================================="
log_info "Deployments: $DEPLOYMENT_COUNT"
log_info "Replicas per deployment: $REPLICAS_PER_DEPLOYMENT"
log_info "Total Pods: $TOTAL_PODS ($DEPLOYMENT_COUNT × $REPLICAS_PER_DEPLOYMENT)"
log_info "Pod Type: $POD_TYPE"
log_info "VLANs: $VLAN_COUNT (vlan$VLAN_START-vlan$((VLAN_START + VLAN_COUNT - 1)))"
log_info "Pods per VLAN: ~$PODS_PER_VLAN"
log_info "Policies: $POLICY_COUNT"
log_info "CIDRs per policy: $CIDRS_PER_POLICY"
log_info "Ports per policy: $PORTS_PER_POLICY"
log_info "Sleep interval: ${SLEEP_INTERVAL}s"
log_info "Namespace: $NAMESPACE"
log_info "Output: $OUTPUT_DIR"
log_info "=========================================="
log_info "Expected ACLs per Pod: ~$EXPECTED_ACLS_PER_POD"
log_info "Total expected ACLs: ~$TOTAL_EXPECTED_ACLS"
log_info "=========================================="
echo ""

# Generate NetworkAttachmentDefinitions for each VLAN
log_info "Generating NetworkAttachmentDefinitions for $VLAN_COUNT VLANs..."
for ((v=0; v<$VLAN_COUNT; v++)); do
    VLAN_ID=$((VLAN_START + v))
    VLAN_NAME="vlan${VLAN_ID}"
    SUBNET_THIRD=$((111 + v))
    SUBNET="${VLAN_BASE_IP}.${SUBNET_THIRD}.0/24"

    cat > "$OUTPUT_DIR/networks/nad-${VLAN_NAME}.yaml" <<EOF
---
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: ${VLAN_NAME}
  namespace: ${NAMESPACE}
spec:
  config: |
    {
      "cniVersion": "0.4.0",
      "name": "${VLAN_NAME}-net",
      "type": "ovn-k8s-cni-overlay",
      "topology": "layer2",
      "netAttachDefName": "${NAMESPACE}/${VLAN_NAME}",
      "subnets": "${SUBNET}"
    }
EOF

    log_info "  Generated NAD: ${VLAN_NAME} (${SUBNET}, layer2)"
done

# Generate Pods or Deployments
log_info "Generating $DEPLOYMENT_COUNT ${POD_TYPE}s (with $REPLICAS_PER_DEPLOYMENT replicas each = $TOTAL_PODS total pods)..."
for ((i=0; i<$DEPLOYMENT_COUNT; i++)); do
    VLAN_INDEX=$((i % VLAN_COUNT))
    VLAN_ID=$((VLAN_START + VLAN_INDEX))
    VLAN_NAME="vlan${VLAN_ID}"
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
    vlan: ${VLAN_NAME}
    test: customer-scale
spec:
  replicas: ${REPLICAS_PER_DEPLOYMENT}
  selector:
    matchLabels:
      app: ${POD_NAME}
  template:
    metadata:
      annotations:
        k8s.v1.cni.cncf.io/networks: ${NAMESPACE}/${VLAN_NAME}
      labels:
        app: ${POD_NAME}
        vlan: ${VLAN_NAME}
        test: customer-scale
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
          allowPrivilegeEscalation: false
          seccompProfile:
            type: RuntimeDefault
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
    k8s.v1.cni.cncf.io/networks: ${NAMESPACE}/${VLAN_NAME}
  labels:
    vlan: ${VLAN_NAME}
    test: customer-scale
spec:
  containers:
  - name: nginx
    image: quay.io/openshift-psap/qe/nginx-alpine:multiarch
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
      allowPrivilegeEscalation: false
      seccompProfile:
        type: RuntimeDefault
      capabilities:
        drop:
        - ALL
EOF
    fi

    if [[ $((i % 10)) -eq 0 ]]; then
        echo -ne "\r  Progress: $i/$DEPLOYMENT_COUNT ${POD_TYPE}s"
    fi
done
echo ""
log_info "✓ Generated $DEPLOYMENT_COUNT ${POD_TYPE} manifests ($TOTAL_PODS total pods)"

# Generate MultiNetworkPolicies (customer pattern: CIDR-heavy)
log_info "Generating $POLICY_COUNT MultiNetworkPolicies (CIDR-heavy pattern)..."

# Build VLAN list for policy-for annotation (all VLANs)
VLAN_LIST=""
for ((v=0; v<$VLAN_COUNT; v++)); do
    VLAN_ID=$((VLAN_START + v))
    VLAN_NAME="vlan${VLAN_ID}"
    if [[ $v -eq 0 ]]; then
        VLAN_LIST="${NAMESPACE}/${VLAN_NAME}"
    else
        VLAN_LIST="${VLAN_LIST},${NAMESPACE}/${VLAN_NAME}"
    fi
done

for ((p=0; p<$POLICY_COUNT; p++)); do
    # Generate realistic long policy names matching customer pattern
    POLICY_TYPES=("birthright-from-any-sdn-server" "birthright-to-any-sdn-server" "any-to-all-internal-nets" "skynet-policy-rule" "default-network-services" "default-internet-access")
    TYPE_INDEX=$((p % 6))
    POLICY_PREFIX="${POLICY_TYPES[$TYPE_INDEX]}"

    # Generate zone ID (matching customer's zone numbers)
    ZONE_ID=$((100000 + RANDOM % 700000))

    DIRECTION=$((p % 2))  # Alternate between egress (0) and ingress (1)

    if [[ $DIRECTION -eq 0 ]]; then
        POLICY_TYPE="egress"
    else
        POLICY_TYPE="ingress"
    fi

    # Format: {prefix}-zone-{zoneID}-{direction} (matching customer pattern)
    POLICY_NAME="${POLICY_PREFIX}-zone-${ZONE_ID}-${POLICY_TYPE}"

    cat > "$OUTPUT_DIR/policies/${POLICY_NAME}.yaml" <<EOF
---
apiVersion: k8s.cni.cncf.io/v1beta1
kind: MultiNetworkPolicy
metadata:
  name: ${POLICY_NAME}
  namespace: ${NAMESPACE}
  annotations:
    k8s.v1.cni.cncf.io/policy-for: ${VLAN_LIST}
  labels:
    test: customer-scale
spec:
  podSelector: {}
  policyTypes:
  - $(echo $POLICY_TYPE | tr '[:lower:]' '[:upper:]' | sed 's/EGRESS/Egress/; s/INGRESS/Ingress/')
  ${POLICY_TYPE}:
  - ports:
EOF

    # Add few ports (matching customer pattern: ~2 ports)
    for port in 22 443; do
        cat >> "$OUTPUT_DIR/policies/${POLICY_NAME}.yaml" <<EOF
    - port: ${port}
      protocol: TCP
EOF
    done

    # Add many CIDR blocks (matching customer pattern: ~450 CIDRs)
    if [[ $DIRECTION -eq 0 ]]; then
        echo "    to:" >> "$OUTPUT_DIR/policies/${POLICY_NAME}.yaml"
    else
        echo "    from:" >> "$OUTPUT_DIR/policies/${POLICY_NAME}.yaml"
    fi

    for ((c=0; c<$CIDRS_PER_POLICY; c++)); do
        # Generate diverse CIDR blocks
        TEMP=$((c / 256))
        OCTET1=$((10 + TEMP % 10))
        TEMP2=$((c / 16))
        OCTET2=$((TEMP2 % 256))
        OCTET3=$((c % 256))
        
        # Vary CIDR prefix length for realism
        PREFIX=$((24 + (c % 8)))
        
        cat >> "$OUTPUT_DIR/policies/${POLICY_NAME}.yaml" <<EOF
    - ipBlock:
        cidr: ${OCTET1}.${OCTET2}.${OCTET3}.0/${PREFIX}
EOF
    done

    if [[ $((p % 50)) -eq 0 ]]; then
        echo -ne "\r  Progress: $p/$POLICY_COUNT policies"
    fi
done
echo ""
log_info "✓ Generated $POLICY_COUNT MultiNetworkPolicy manifests"

# Create combined manifest
log_info "Creating combined manifest..."
cat > "$OUTPUT_DIR/all-in-one.yaml" <<EOF
# Generated by: $0
# Date: $(date)
# Configuration:
#   Total Pods: $TOTAL_PODS
#   VLANs: $VLAN_COUNT
#   Policies: $POLICY_COUNT
#   CIDRs per policy: $CIDRS_PER_POLICY
#   Ports per policy: $PORTS_PER_POLICY
#   Expected ACLs: ~$TOTAL_EXPECTED_ACLS
#
EOF

# Add NADs
cat "$OUTPUT_DIR"/networks/*.yaml >> "$OUTPUT_DIR/all-in-one.yaml"

# Add policies
cat "$OUTPUT_DIR"/policies/*.yaml >> "$OUTPUT_DIR/all-in-one.yaml"

# Add Pods
cat "$OUTPUT_DIR"/pods/*.yaml >> "$OUTPUT_DIR/all-in-one.yaml"

log_info "✓ Created combined manifest: $OUTPUT_DIR/all-in-one.yaml"

# Create summary
cat > "$OUTPUT_DIR/SUMMARY.md" <<EOF
# Customer-Scale MultiNetworkPolicy Deployment Summary

**Generated**: $(date)
**Namespace**: $NAMESPACE

## Configuration

| Component | Count | Details |
|-----------|-------|---------|
| **Deployments** | $DEPLOYMENT_COUNT | $POD_TYPE with $REPLICAS_PER_DEPLOYMENT replicas each |
| **Total Pods** | $TOTAL_PODS | $DEPLOYMENT_COUNT × $REPLICAS_PER_DEPLOYMENT |
| **VLANs** | $VLAN_COUNT | vlan$VLAN_START-vlan$((VLAN_START + VLAN_COUNT - 1)) |
| **Pods per VLAN** | ~$PODS_PER_VLAN | Distributed evenly |
| **Policies** | $POLICY_COUNT | CIDR-heavy pattern |
| **CIDRs per policy** | $CIDRS_PER_POLICY | Matching customer avg |
| **Ports per policy** | $PORTS_PER_POLICY | Matching customer avg |

## VLANs (Layer2 Topology)

$(for ((v=0; v<$VLAN_COUNT; v++)); do
    VLAN_ID=$((VLAN_START + v))
    SUBNET_THIRD=$((111 + v))
    echo "- **vlan${VLAN_ID}**: ${VLAN_BASE_IP}.${SUBNET_THIRD}.0/24 (ovn-k8s-cni-overlay, layer2)"
done)

## Policy Pattern

**Customer-like CIDR-heavy policies**:
- **Ports**: $PORTS_PER_POLICY (TCP 22, 443)
- **CIDR blocks**: $CIDRS_PER_POLICY diverse IP ranges
- **Applied to**: All $VLAN_COUNT VLANs simultaneously
- **Direction**: Alternating egress/ingress

## Expected ACL Count

**Per Pod**: ~$EXPECTED_ACLS_PER_POD ACLs
**Total**: ~$TOTAL_EXPECTED_ACLS ACLs

**Scaling to customer full environment**:
- 1,000 Pods × 485 policies × 450 CIDRs × 2 ports = ~**3,745,000 ACLs**

## Deployment

### Apply to Cluster
\`\`\`bash
# Create namespace
oc create namespace $NAMESPACE 2>/dev/null || true

# Apply all resources
oc apply -f $OUTPUT_DIR/all-in-one.yaml
\`\`\`

### Monitor
\`\`\`bash
# Watch Pods
oc get deployment,pods -n $NAMESPACE -w

# Watch policies
oc get multi-networkpolicies -n $NAMESPACE

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
log_info "  - VLANs: $VLAN_COUNT NADs (layer2 topology)"
log_info "  - Deployments: $DEPLOYMENT_COUNT manifests ($POD_TYPE, $REPLICAS_PER_DEPLOYMENT replicas each)"
log_info "  - Total Pods: $TOTAL_PODS ($DEPLOYMENT_COUNT × $REPLICAS_PER_DEPLOYMENT)"
log_info "  - Policies: $POLICY_COUNT (CIDR-heavy pattern)"
log_info "  - Combined: all-in-one.yaml"
echo ""
log_info "Expected ACL increase: ~$TOTAL_EXPECTED_ACLS ACLs"
echo ""

if [[ "$APPLY" == "true" ]]; then
    log_info "Applying to cluster..."

    # Check and enable MultiNetworkPolicy support
    enable_multinetworkpolicy
    if [[ $? -ne 0 ]]; then
        log_error "Failed to enable MultiNetworkPolicy support"
        exit 1
    fi
    echo ""

    # Create namespace
    oc create namespace "$NAMESPACE" 2>/dev/null || log_warn "Namespace $NAMESPACE already exists"

    # Apply NADs
    log_info "Applying NetworkAttachmentDefinitions..."
    oc apply -f "$OUTPUT_DIR/networks/"

    # Apply policies one by one with sleep
    log_info "Applying MultiNetworkPolicies one by one (${SLEEP_INTERVAL}s delay between each)..."
    TOTAL_POLICIES=$(ls -1 "$OUTPUT_DIR/policies"/*.yaml 2>/dev/null | wc -l)
    CURRENT_POLICY=0
    for policy_file in "$OUTPUT_DIR/policies"/*.yaml; do
        CURRENT_POLICY=$((CURRENT_POLICY + 1))
        log_info "  Applying policy $CURRENT_POLICY/$TOTAL_POLICIES: $(basename "$policy_file")"
        oc apply -f "$policy_file"
        sleep "$SLEEP_INTERVAL"
    done
    log_info "✓ Applied all $TOTAL_POLICIES MultiNetworkPolicies"

    # Apply Pods/Deployments one by one with sleep
    log_info "Applying ${POD_TYPE}s one by one (${SLEEP_INTERVAL}s delay between each)..."
    TOTAL_DEPLOYMENTS=$(ls -1 "$OUTPUT_DIR/pods"/*.yaml 2>/dev/null | wc -l)
    CURRENT_DEPLOYMENT=0
    for deployment_file in "$OUTPUT_DIR/pods"/*.yaml; do
        CURRENT_DEPLOYMENT=$((CURRENT_DEPLOYMENT + 1))
        log_info "  Applying ${POD_TYPE} $CURRENT_DEPLOYMENT/$TOTAL_DEPLOYMENTS: $(basename "$deployment_file")"
        oc apply -f "$deployment_file"
        sleep "$SLEEP_INTERVAL"
    done
    log_info "✓ Applied all $TOTAL_DEPLOYMENTS ${POD_TYPE}s"

    log_info "✓ Resources applied to cluster"
    log_info ""
    log_info "Monitor with:"
    log_info "  oc get deployment,pods -n $NAMESPACE -w"
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
