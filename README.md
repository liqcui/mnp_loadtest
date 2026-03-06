# MultiNetworkPolicy Loadtest Scripts

Comprehensive testing suite for OpenShift MultiNetworkPolicy (MNP) scalability and performance, simulating customer-scale deployments with high ACL counts.

## Overview

This collection of scripts enables testing of MultiNetworkPolicy implementations at scale, supporting both Pod-based and VM-based workloads. The scripts generate realistic network topologies with multiple VLANs, CIDR-heavy policies, and thousands of resources to validate OVN-Kubernetes performance under customer-like conditions.

## Quick Start

### Prerequisites

```bash
# Required
- OpenShift 4.12+ cluster with OVN-Kubernetes networking
- oc CLI installed and authenticated
- Cluster-admin or namespace-admin permissions

# Optional (for VM-based tests)
- KubeVirt/OpenShift Virtualization installed
- virtctl CLI tool
```

### Quick Test (Pods - 10 pods, 5 policies)

```bash
cd /path/to/loadtest
./generate-customer-scale-pods.sh --total-pods 10 --policy-count 5 --apply
```

### Full Scale Test (1000 pods, 385 policies, 450 CIDRs per policy)

**Gradual Mode (RECOMMENDED):**
```bash
# Apply in steps: safer, prevents cluster overload
./generate-customer-scale-pods.sh \
  --deployment-count 100 \
  --replicas 10 \
  --policy-count 385 \
  --cidrs-per-policy 450 \
  --gradual \
  --step-size 10 \
  --step-interval 30 \
  --apply
```

**Batch Mode (All at once):**
```bash
# Apply all resources at once: faster but may overwhelm cluster
./generate-customer-scale-pods.sh \
  --deployment-count 100 \
  --replicas 10 \
  --policy-count 385 \
  --cidrs-per-policy 450 \
  --apply
```

### Quick Test (VMs - 10 VMs, 5 policies)

```bash
./generate-customer-scale-vms.sh --total-vms 10 --policy-count 5 --apply
```

## Main Scripts

### 1. generate-customer-scale-pods.sh

**Purpose:** Generate customer-scale deployment with Pods/Deployments and CIDR-heavy MultiNetworkPolicies

**Use Case:** Testing Pod-based workloads with realistic customer patterns

#### Quick Reference: 1000 Pods + 385 Policies + 450 CIDRs

**Gradual Mode (RECOMMENDED):**
```bash
./generate-customer-scale-pods.sh \
  --deployment-count 100 --replicas 10 \
  --policy-count 385 --cidrs-per-policy 450 \
  --gradual --step-size 10 --step-interval 30 \
  --apply
```

**Batch Mode (All at once):**
```bash
./generate-customer-scale-pods.sh \
  --deployment-count 100 --replicas 10 \
  --policy-count 385 --cidrs-per-policy 450 \
  --apply
```

#### More Examples

```bash
# Default: 100 deployments with 1 replica each (100 pods)
./generate-customer-scale-pods.sh --apply

# Small test (10 deployments, 1 replica each, 5 policies)
./generate-customer-scale-pods.sh \
  --deployment-count 10 \
  --replicas 1 \
  --policy-count 5 \
  --apply

# Medium test (50 deployments, 2 replicas each = 100 pods, 25 policies)
./generate-customer-scale-pods.sh \
  --deployment-count 50 \
  --replicas 2 \
  --policy-count 25 \
  --apply

# Large scale GRADUAL deployment (100 deployments, 10 replicas = 1000 pods)
# RECOMMENDED: Use gradual mode for large deployments to prevent cluster overload
./generate-customer-scale-pods.sh \
  --deployment-count 100 \
  --replicas 10 \
  --policy-count 385 \
  --cidrs-per-policy 450 \
  --gradual \
  --step-size 10 \
  --step-interval 30 \
  --apply

# Add more pods to existing environment (no NADs/policies)
./generate-customer-scale-pods.sh \
  --deployment-count 50 \
  --replicas 10 \
  --deployments-only \
  --gradual \
  --step-size 5 \
  --apply

# Large scale batch deployment (all at once - may overwhelm cluster)
# WARNING: Requires large cluster (5+ worker nodes, 32GB+ RAM per node)
./generate-customer-scale-pods.sh \
  --deployment-count 500 \
  --replicas 2 \
  --policy-count 385 \
  --cidrs-per-policy 450 \
  --apply
```

**Key Features:**
- Creates deployments with configurable replica count (default: 100 deployments × 1 replica = 100 pods)
- Generates **CIDR-heavy policies** (450 CIDRs × 2 ports each by default)
- **Gradual deployment mode** - Apply pods in steps to prevent cluster overload (NEW!)
- **Deployments-only mode** - Add pods without creating NADs/policies (NEW!)
- Configurable **sleep interval** between resource creation (default: 10s, recommended: 20-30s for large scale)
- Expected ACL count: **~173 ACLs per pod** (with 385 policies, 450 CIDRs)
- Uses realistic policy names matching customer patterns
- Supports dry-run mode for validation

**Output Structure:**
```
generated-customer-scale-pods/
├── networks/                          # NetworkAttachmentDefinitions
│   └── nad-vlan{750-758}.yaml         # 9 VLAN definitions
├── pods/                              # Deployment manifests
│   └── loadtest-pod-{0-N}.yaml        # N deployment files (configurable replicas)
├── policies/                          # MultiNetworkPolicy manifests
│   └── {policy-name}.yaml             # Policy files (configurable count)
├── all-in-one.yaml                    # Combined manifest
└── SUMMARY.md                         # Deployment summary
```

**Configuration Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--deployment-count` | 100 | Number of deployments to create |
| `--replicas` | 1 | Replicas per deployment |
| `--total-pods` | (auto-calc) | Total pods (overrides deployment-count × replicas) |
| `--pod-type` | deployment | Pod type: deployment or pod |
| `--policy-count` | 485 | Number of MultiNetworkPolicies |
| `--cidrs-per-policy` | 450 | CIDR blocks per policy |
| `--sleep-interval` | 10 | Sleep seconds between deployments (use 20-30 for large scale) |
| `--vlan-count` | 9 | Number of VLANs (vlan750-vlan758) |
| `--namespace` | loadtest | Target namespace |
| `--deployments-only` | false | Create only deployments/pods (skip NADs and policies) |
| `--gradual` | false | Apply deployments gradually in steps |
| `--step-size` | 10 | Deployments per step (only with --gradual) |
| `--step-interval` | 30 | Sleep seconds between steps (only with --gradual) |
| `--dry-run` | false | Generate files without applying |
| `--apply` | false | Apply to cluster |
| `--clean` | - | Clean up all resources |

**Expected Results:**

| Scale | Deployments | Replicas | Total Pods | Policies | Expected ACLs | Time to Deploy |
|-------|-------------|----------|------------|----------|---------------|----------------|
| Small | 10 | 1 | 10 | 5 | ~450 | ~2 min |
| Medium | 100 | 1 | 100 | 25 | ~11,250 | ~17 min |
| Large | 500 | 2 | 1,000 | 385 | ~173,000 | ~2.8 hrs (10s) |
| X-Large | 2000 | 1 | 2,000 | 385 | ~346,000 | ~11 hrs (20s) |

**Note:** Time estimates include policy application time. Use `--sleep-interval 20` or higher for large deployments to avoid OVN/OVS overload.

#### Full Customer-Scale Deployment: Batch vs Gradual

**Deployment Target:**
- **1000 Pods** (100 deployments × 10 replicas)
- **385 MultiNetworkPolicies**
- **450 CIDR rules** per policy
- **Expected Result:** ~173,250 ACLs (173 ACLs per pod)

---

##### Option 1: Batch Mode (All Resources at Once)

Apply all resources in one batch - faster but may overwhelm cluster.

```bash
./generate-customer-scale-pods.sh \
  --deployment-count 100 \
  --replicas 10 \
  --policy-count 385 \
  --cidrs-per-policy 450 \
  --apply
```

**Timeline:**
1. Generate manifests: ~2 seconds
2. Apply 9 NADs: ~5 seconds (all at once)
3. Apply 385 policies: ~10 seconds (all at once)
4. Apply 100 deployments: ~10 seconds (all at once)
5. Pods starting: ~5-15 minutes (all 1000 pods simultaneously)

**Total time:** ~5-15 minutes (fast but risky)

**Pros:**
- Fastest deployment
- Simple, single command

**Cons:**
- May overwhelm cluster control plane
- All 1000 pods start simultaneously
- Difficult to debug if issues occur
- Can cause "timed out waiting for OVS port binding" errors
- May cause ovnkube-node pod crashes

**When to use:**
- Small clusters with <100 pods
- Testing environments only
- When cluster has significant spare capacity

---

##### Option 2: Gradual Mode (Step-by-Step) - RECOMMENDED

Apply deployments in controlled steps - slower but safer and more reliable.

```bash
./generate-customer-scale-pods.sh \
  --deployment-count 100 \
  --replicas 10 \
  --policy-count 385 \
  --cidrs-per-policy 450 \
  --gradual \
  --step-size 10 \
  --step-interval 30 \
  --apply
```

**Timeline:**
1. Generate manifests: ~2 seconds
2. Apply 9 NADs: ~5 seconds (all at once)
3. Apply 385 policies: ~10 seconds (all at once)
4. **Apply 100 deployments in 10 steps:**
   - Step 1: Apply 10 deployments (100 pods) → wait 30s
   - Step 2: Apply 10 deployments (100 pods) → wait 30s
   - Step 3: Apply 10 deployments (100 pods) → wait 30s
   - ... (continues for 10 steps)
   - Step 10: Apply 10 deployments (100 pods) → done
5. Pods starting: Gradual (100 pods every 30 seconds)

**Total time:** ~5-10 minutes (controlled and predictable)

**Step Output Example:**
```
[INFO] Step 1: Applying deployments 1-10 of 100
[INFO]   Deployments in this step: 10
[INFO]   Pods in this step: 100 (10 × 10)
[INFO]   Applying: loadtest-pod-0.yaml
[INFO]   Applying: loadtest-pod-1.yaml
...
[INFO]   Applying: loadtest-pod-9.yaml
[INFO] ✓ Step 1 complete. Total pods created so far: ~100
[INFO] Waiting 30s before next step...

[INFO] Step 2: Applying deployments 11-20 of 100
[INFO]   Deployments in this step: 10
[INFO]   Pods in this step: 100 (10 × 10)
...
```

**Pros:**
- Prevents cluster control plane overload
- Allows monitoring between steps
- Can interrupt if issues detected
- Better visibility into deployment progress
- More predictable resource consumption
- Significantly reduces OVS timeout errors

**Cons:**
- Takes slightly longer than batch mode
- More verbose output

**When to use:**
- Production environments
- Large deployments (500+ pods)
- First-time large-scale testing
- When cluster capacity is uncertain

---

##### Comparison Table

| Aspect | Batch Mode | Gradual Mode (10/step, 30s) |
|--------|------------|----------------------------|
| **Command** | `--apply` | `--gradual --step-size 10 --step-interval 30 --apply` |
| **Total Time** | ~5-15 min | ~5-10 min |
| **NADs Applied** | All at once (9 NADs) | All at once (9 NADs) |
| **Policies Applied** | All at once (385 policies) | All at once (385 policies) |
| **Deployments Applied** | All at once (100 deployments) | In 10 steps (10 deployments/step) |
| **Pods Starting** | All at once (1000 pods) | Gradually (100 pods every 30s) |
| **Cluster Load** | High spike | Distributed evenly |
| **Monitoring Difficulty** | Hard (everything happens fast) | Easy (step-by-step progress) |
| **OVS Timeout Risk** | High | Low |
| **Interruptible** | No | Yes (Ctrl+C between steps) |
| **Recommended For** | <100 pods | 500+ pods |

**See [GRADUAL_DEPLOYMENT_GUIDE.md](./GRADUAL_DEPLOYMENT_GUIDE.md) for detailed usage and examples.**

---

##### Step-by-Step: Creating 1000 Pods with 385 Policies

**Complete Walkthrough - Gradual Mode (Recommended)**

```bash
# Step 1: Navigate to loadtest directory
cd /path/to/loadtest

# Step 2: (Optional) Check baseline ACL count
./demo-acl-check.sh > baseline-acls.txt

# Step 3: Deploy with gradual mode
./generate-customer-scale-pods.sh \
  --deployment-count 100 \
  --replicas 10 \
  --policy-count 385 \
  --cidrs-per-policy 450 \
  --gradual \
  --step-size 10 \
  --step-interval 30 \
  --apply 2>&1 | tee deployment-$(date +%Y%m%d-%H%M%S).log

# What you'll see:
# [INFO] Customer-Scale MNP Generator
# [INFO] ==========================================
# [INFO] Deployments: 100
# [INFO] Replicas per deployment: 10
# [INFO] Total Pods: 1000 (100 × 10)
# [INFO] VLANs: 9 (vlan750-vlan758)
# [INFO] Policies: 385
# [INFO] CIDRs per policy: 450
# [INFO] Gradual deployment: 10 deployments per step, 10 total steps
# [INFO] Step interval: 30s
# [INFO] Expected ACLs per Pod: ~173
# [INFO] Total expected ACLs: ~173,250
# [INFO] ==========================================
#
# [INFO] Generating NetworkAttachmentDefinitions for 9 VLANs...
# [INFO] Generating 100 deployments (with 10 replicas each = 1000 total pods)...
# [INFO] Generating 385 MultiNetworkPolicies (CIDR-heavy pattern)...
#
# [INFO] Applying to cluster...
# [INFO] Applying NetworkAttachmentDefinitions...
# [INFO] Applying MultiNetworkPolicies...
# [INFO] Applying deployments gradually in steps...
#
# [INFO] Step 1: Applying deployments 1-10 of 100
# [INFO]   Deployments in this step: 10
# [INFO]   Pods in this step: 100 (10 × 10)
# ... (10 steps total, 30s wait between each)
# [INFO] ✓ All 100 deployments applied in 10 steps

# Step 4: Monitor deployment in another terminal (while step 3 runs)
watch -n 10 'oc get deployment,pods -n loadtest | head -25'

# Step 5: Wait for all pods to reach Running state (~5-10 minutes)
oc get pods -n loadtest -w

# Step 6: Verify ACL count
./demo-acl-check.sh

# Expected output:
# Total ACLs in OVN NB: ~173,250
# (173 ACLs per pod × 1000 pods)

# Step 7: (Optional) Compare with baseline
./demo-acl-check.sh > after-acls.txt
diff baseline-acls.txt after-acls.txt

# Step 8: Cleanup when done
./clean-customer-scale-pods.sh
```

**Complete Walkthrough - Batch Mode**

```bash
# Step 1: Navigate to loadtest directory
cd /path/to/loadtest

# Step 2: Deploy all at once (CAUTION: may overwhelm cluster)
./generate-customer-scale-pods.sh \
  --deployment-count 100 \
  --replicas 10 \
  --policy-count 385 \
  --cidrs-per-policy 450 \
  --apply 2>&1 | tee deployment-$(date +%Y%m%d-%H%M%S).log

# What you'll see:
# [INFO] Customer-Scale MNP Generator
# [INFO] ==========================================
# [INFO] Deployments: 100
# [INFO] Replicas per deployment: 10
# [INFO] Total Pods: 1000 (100 × 10)
# [INFO] Policies: 385
# [INFO] CIDRs per policy: 450
# [INFO] Expected ACLs per Pod: ~173
# [INFO] Total expected ACLs: ~173,250
# [INFO] ==========================================
#
# [INFO] Applying to cluster...
# [INFO] Applying NetworkAttachmentDefinitions...
# [INFO] Applying MultiNetworkPolicies...
# [INFO] Applying deployments...
# [INFO] ✓ Resources applied to cluster
# (All 100 deployments applied at once)

# Step 3: Monitor deployment (all 1000 pods start simultaneously)
watch -n 10 'oc get deployment,pods -n loadtest | head -25'

# Step 4: Check for pod errors (common in batch mode)
oc get pods -n loadtest | grep -v Running

# If you see ContainerCreating errors:
# "timed out waiting for OVS port binding"
# This means cluster was overwhelmed - use gradual mode instead

# Step 5: Verify ACL count (once all pods are Running)
./demo-acl-check.sh

# Step 6: Cleanup
./clean-customer-scale-pods.sh
```

---

#### Deployments-Only Mode

Add more pods to an existing environment without recreating NADs and policies:

```bash
# Add 500 more pods to existing network configuration
./generate-customer-scale-pods.sh \
  --deployment-count 50 \
  --replicas 10 \
  --deployments-only \
  --gradual \
  --step-size 5 \
  --apply
```

**Use cases:**
- Scaling up an existing test environment
- Testing pod density without changing network policies
- Incremental capacity testing

---

### 2. generate-customer-scale-vms.sh

**Purpose:** Generate customer-scale VirtualMachines with CIDR-heavy MultiNetworkPolicies

**Use Case:** Testing VM-based workloads (requires OpenShift Virtualization/KubeVirt)

```bash
# Small test (10 VMs, proportional policies)
./generate-customer-scale-vms.sh \
  --total-vms 10 \
  --policy-count 5 \
  --apply

# Medium test (50 VMs, ~25 policies)
./generate-customer-scale-vms.sh \
  --total-vms 50 \
  --policy-count 25 \
  --apply

# Large test (100 VMs, full customer pattern)
./generate-customer-scale-vms.sh \
  --total-vms 100 \
  --full-scale-rules \
  --apply
```

**Key Features:**
- Creates VirtualMachine objects (not Pods)
- Same CIDR-heavy policy pattern as pods script
- Supports `--full-scale-rules` flag for complete customer simulation
- Each VM gets secondary network interfaces (via NetworkAttachmentDefinitions)
- Policies applied across all VLANs simultaneously

**Output Structure:**
```
generated-customer-scale-vms/
├── networks/                          # NetworkAttachmentDefinitions
│   └── nad-vlan{750-758}.yaml
├── vms/                               # VirtualMachine manifests
│   └── loadtest-vm-{n}.yaml
├── policies/                          # MultiNetworkPolicy manifests
│   └── {policy-name}.yaml
├── all-in-one.yaml
└── SUMMARY.md
```

**Configuration Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--total-vms` | 10 | Number of VirtualMachines |
| `--policy-count` | 485 | Number of policies (or use --full-scale-rules) |
| `--full-scale-rules` | - | Use full customer pattern (485 policies) |
| `--cidrs-per-policy` | 450 | CIDR blocks per policy |
| `--vlan-count` | 9 | Number of VLANs |
| `--namespace` | loadtest | Target namespace |
| `--apply` | false | Apply to cluster |
| `--clean` | - | Clean up resources |

**VM Specifications:**
- **Image:** Fedora Cloud (via DataVolume/PVC)
- **CPU:** 1 core
- **Memory:** 2Gi
- **Disk:** 10Gi
- **Networks:** Primary (pod network) + Secondary (VLAN interface)

---

### 3. generate-vms-with-mnp.sh

**Purpose:** Generate VMs with MultiNetworkPolicies (simplified version)

**Use Case:** Basic VM + MNP testing without full customer scale

```bash
# Small deployment
./generate-vms-with-mnp.sh \
  --total-vms 5 \
  --policy-count 3 \
  --apply

# Medium deployment
./generate-vms-with-mnp.sh \
  --total-vms 20 \
  --policy-count 10 \
  --apply
```

**Key Features:**
- Similar to `generate-customer-scale-vms.sh` but with simpler configuration
- Good for quick VM + MNP validation tests
- Less resource-intensive than full customer-scale script

**Output Structure:**
```
generated-vms-mnp/
├── networks/                          # NetworkAttachmentDefinitions
├── vms/                               # VirtualMachine manifests
└── policies/                          # MultiNetworkPolicy manifests
```

---

## Supporting Scripts

### Cleanup

**clean-customer-scale-pods.sh** - Clean up pod-based deployments
```bash
# Clean all resources (deployments, policies, NADs)
./clean-customer-scale-pods.sh

# Clean only deployments/pods (keep policies and NADs)
./clean-customer-scale-pods.sh --deployments-only

# Dry run to preview what would be deleted
./clean-customer-scale-pods.sh --dry-run

# Clean specific namespace
./clean-customer-scale-pods.sh --namespace my-test
```

**Options:**
- `--deployments-only` - Delete only deployments/pods (skip policies and NADs)
- `--skip-deployments` - Skip deleting deployments/pods
- `--skip-policies` - Skip deleting multi-networkpolicies
- `--skip-nads` - Skip deleting network attachment definitions
- `--dry-run` - Show what would be deleted without deleting
- `--namespace NS` - Specify namespace (default: loadtest)

### Monitoring & Validation

**demo-acl-check.sh** - Quick ACL count check
```bash
./demo-acl-check.sh
```

**check-acl-count.sh** - Detailed ACL analysis
```bash
# Quick count
./check-acl-count.sh --method ovn-nbctl

# Detailed breakdown with sample ACLs
./check-acl-count.sh --method all --show-acls

# Count by port group
./check-acl-count.sh --by-port-group
```

**monitor-vms.sh** - Monitor VM status
```bash
# One-time check
./monitor-vms.sh --once

# Continuous monitoring
./monitor-vms.sh
```

**test-connectivity.sh** - Test network connectivity
```bash
./test-connectivity.sh
```

---

## Workflow Examples

### Example 1: Full Pod-Based Customer Simulation (Gradual Mode - RECOMMENDED)

```bash
# 1. Generate and apply resources (1000 pods, 385 policies) GRADUALLY
./generate-customer-scale-pods.sh \
  --deployment-count 100 \
  --replicas 10 \
  --policy-count 385 \
  --cidrs-per-policy 450 \
  --gradual \
  --step-size 10 \
  --step-interval 30 \
  --apply 2>&1 | tee deployment.log

# 2. Monitor progress (in another terminal)
watch -n 10 'oc get deployment,pods -n loadtest | head -20'

# 3. Monitor ACL count during deployment
watch -n 30 './demo-acl-check.sh'

# 4. Wait for deployment completion (~10 minutes for deployments)
# Progress shown: Step 1/10, Step 2/10, etc.

# 5. Verify final ACL count
./demo-acl-check.sh
# Expected: ~346,000 ACLs (346 ACLs per pod × 1000 pods)

# 6. Cleanup when done
./clean-customer-scale-pods.sh
```

### Example 1b: Full Pod-Based Customer Simulation (Batch Mode)

```bash
# 1. Generate and apply resources (1000 pods, 385 policies) ALL AT ONCE
# WARNING: May overwhelm cluster - gradual mode recommended
./generate-customer-scale-pods.sh \
  --total-pods 1000 \
  --policy-count 385 \
  --cidrs-per-policy 450 \
  --apply 2>&1 | tee deployment.log

# 2. Monitor progress (in another terminal)
watch -n 10 'oc get deployment,pods -n loadtest | head -20'

# 3. Wait for deployment completion (~17 minutes)
# Watch: deployment.log

# 4. Check ACL count
./demo-acl-check.sh

# 5. Verify expected ACL count
# Expected: ~346,000 ACLs (346 ACLs per pod × 1000 pods)

# 6. Cleanup when done
./clean-customer-scale-pods.sh
```

### Example 2: Progressive Load Testing with Gradual Scaling

```bash
# Step 1: Start small (100 pods)
./generate-customer-scale-pods.sh \
  --deployment-count 100 \
  --replicas 1 \
  --policy-count 5 \
  --apply
./demo-acl-check.sh
# Wait and observe cluster

# Step 2: Add more pods to existing setup (400 more pods = 500 total)
./generate-customer-scale-pods.sh \
  --deployment-count 40 \
  --replicas 10 \
  --deployments-only \
  --gradual \
  --step-size 5 \
  --apply
./demo-acl-check.sh
# Wait and observe cluster

# Step 3: Scale to full (add 500 more pods = 1000 total)
./generate-customer-scale-pods.sh \
  --deployment-count 50 \
  --replicas 10 \
  --deployments-only \
  --gradual \
  --step-size 10 \
  --apply
./demo-acl-check.sh

# Step 4: Add more policies to full deployment
./clean-customer-scale-pods.sh
./generate-customer-scale-pods.sh \
  --deployment-count 100 \
  --replicas 10 \
  --policy-count 385 \
  --gradual \
  --step-size 10 \
  --apply
./demo-acl-check.sh
```

### Example 3: VM-Based Testing

```bash
# 1. Verify KubeVirt is installed
oc get csv -n openshift-cnv | grep kubevirt

# 2. Generate VM-based deployment
./generate-customer-scale-vms.sh \
  --total-vms 10 \
  --policy-count 10 \
  --cidrs-per-policy 450 \
  --apply

# 3. Monitor VMs
./monitor-vms.sh --once

# 4. Wait for VMs to be Running
oc get vmi -n loadtest -w

# 5. Check ACL count
./demo-acl-check.sh

# 6. Test connectivity (once VMs are running)
./test-connectivity.sh

# 7. Cleanup
./generate-customer-scale-vms.sh --clean
```

### Example 4: Dry-Run Validation

```bash
# Generate files without applying
./generate-customer-scale-pods.sh \
  --total-pods 1000 \
  --policy-count 385 \
  --dry-run

# Review generated files
ls -lh generated-customer-scale-pods/
cat generated-customer-scale-pods/SUMMARY.md

# Review a sample policy
cat generated-customer-scale-pods/policies/any-to-all-internal-nets-zone-*.yaml | head -50

# Apply manually if satisfied
oc create namespace loadtest
oc apply -f generated-customer-scale-pods/all-in-one.yaml
```

---

## Policy Patterns

All generation scripts create **customer-like CIDR-heavy policies** matching real-world patterns:

### Policy Types Generated

1. **any-to-all-internal-nets-zone-{ID}-{direction}** - Internal network access
2. **birthright-from-any-sdn-server-zone-{ID}-{direction}** - SDN server access
3. **birthright-to-any-sdn-server-zone-{ID}-{direction}** - SDN server ingress
4. **skynet-policy-rule-zone-{ID}-{direction}** - Application-specific rules
5. **default-network-services-zone-{ID}-{direction}** - Network service access
6. **default-internet-access-zone-{ID}-{direction}** - Internet egress

### Policy Characteristics

- **CIDR-heavy:** ~450 CIDR blocks per policy, 2 ports (TCP 22, 443)
- **Multi-VLAN:** Policies apply to all 9 VLANs simultaneously via annotation
- **Alternating direction:** Egress and ingress policies distributed evenly
- **Realistic naming:** Matches customer zone-based naming convention

### Example Policy Structure

```yaml
apiVersion: k8s.cni.cncf.io/v1beta1
kind: MultiNetworkPolicy
metadata:
  name: any-to-all-internal-nets-zone-123456-egress
  namespace: loadtest
  annotations:
    k8s.v1.cni.cncf.io/policy-for: loadtest/vlan750,loadtest/vlan751,...
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - ports:
    - port: 22
      protocol: TCP
    - port: 443
      protocol: TCP
    to:
    - ipBlock:
        cidr: 10.0.0.0/24
    - ipBlock:
        cidr: 10.0.1.0/24
    # ... 448 more CIDR blocks
```

---

## Network Topology

### VLAN Configuration

All scripts create **9 VLANs** (vlan750-vlan758) using layer2 topology:

| VLAN | Subnet | Topology | CNI Plugin |
|------|--------|----------|------------|
| vlan750 | 10.234.111.0/24 | layer2 | ovn-k8s-cni-overlay |
| vlan751 | 10.234.112.0/24 | layer2 | ovn-k8s-cni-overlay |
| vlan752 | 10.234.113.0/24 | layer2 | ovn-k8s-cni-overlay |
| vlan753 | 10.234.114.0/24 | layer2 | ovn-k8s-cni-overlay |
| vlan754 | 10.234.115.0/24 | layer2 | ovn-k8s-cni-overlay |
| vlan755 | 10.234.116.0/24 | layer2 | ovn-k8s-cni-overlay |
| vlan756 | 10.234.117.0/24 | layer2 | ovn-k8s-cni-overlay |
| vlan757 | 10.234.118.0/24 | layer2 | ovn-k8s-cni-overlay |
| vlan758 | 10.234.119.0/24 | layer2 | ovn-k8s-cni-overlay |

### Pod/VM Distribution

- Pods/VMs distributed evenly across VLANs (round-robin)
- Each Pod/VM gets one secondary network interface
- Policies apply to all VLANs simultaneously

---

## Performance Expectations

### ACL Generation Rate

| Operation | Rate | Notes |
|-----------|------|-------|
| Policy creation | 1 policy / 10s | Controlled rollout |
| Deployment creation | 1 deployment / 10s | Controlled rollout |
| ACL generation (OVN) | Varies | Depends on cluster load |

### Full-Scale Deployment Timeline

**1000 Pods, 385 Policies:**

1. **Manifest generation:** ~1-2 seconds
2. **NAD creation:** ~5 seconds (9 VLANs)
3. **Policy application:** ~64 minutes (385 policies × 10s)
4. **Deployment application:** ~17 minutes (100 deployments × 10s)
5. **Pod startup:** ~10-30 minutes (depending on cluster)
6. **ACL propagation:** ~5-10 minutes (OVN processing)

**Total:** ~1.5-2 hours for complete deployment

### Resource Requirements

**Small Cluster (10 pods/VMs, 5 policies):**
- 1 worker node, 4 CPU, 16GB RAM
- Expected: ~4,500 ACLs

**Medium Cluster (50-100 pods/VMs, 25-50 policies):**
- 2-3 worker nodes, 8 CPU, 32GB RAM each
- Expected: ~25,000-50,000 ACLs

**Large Cluster (1000 pods, 385 policies):**
- 5+ worker nodes, 8+ CPU, 32GB+ RAM each
- Expected: ~346,000 ACLs
- ~100GB storage for logs/data

---

## Troubleshooting

### Issue: Pods stuck in ContainerCreating - "timed out waiting for OVS port binding"

**Cause:** OVN/OVS controllers overwhelmed when creating too many pods simultaneously

**Symptoms:**
```bash
# Check pod events
oc describe pod <pod-name> -n loadtest
# Shows: "failed to configure pod interface: timed out waiting for OVS port binding"

# Check ovnkube-controller logs
oc logs -n openshift-ovn-kubernetes -l app=ovnkube-node -c ovnkube-controller --tail=50
# Shows: "timed out waiting for OVS port binding (ovn-installed)"
```

**Solution:**
```bash
# Option 1: Increase sleep interval (RECOMMENDED for large scale)
# Use --sleep-interval 20 or 30 for deployments > 500
./generate-customer-scale-pods.sh \
  --deployment-count 2000 \
  --sleep-interval 20 \
  --apply

# Option 2: Delete failed pods and let them retry
oc delete pods -n loadtest --field-selector=status.phase!=Running
# Kubernetes will recreate them, spreading out the load

# Option 3: Reduce deployment scale
./generate-customer-scale-pods.sh --clean
./generate-customer-scale-pods.sh \
  --deployment-count 500 \
  --sleep-interval 20 \
  --apply
```

### Issue: Pods stuck in ContainerCreating - Secondary network not ready

**Cause:** Secondary network attachment not properly configured

**Solution:**
```bash
# Check NAD status
oc get net-attach-def -n loadtest

# Check multus logs
oc logs -n openshift-multus -l app=multus

# Verify OVN status
oc get pods -n openshift-ovn-kubernetes
```

### Issue: High ACL count but pods not matching policies

**Cause:** Policy selector mismatch or VLAN annotation issue

**Solution:**
```bash
# Verify policy applies to correct VLANs
oc get multinetworkpolicy -n loadtest {policy-name} -o yaml | grep policy-for

# Check pod labels
oc get pod -n loadtest {pod-name} --show-labels

# Verify pod has secondary network
oc get pod -n loadtest {pod-name} -o jsonpath='{.metadata.annotations}'
```

### Issue: OVN pod crashes or high memory usage

**Cause:** Too many ACLs for cluster capacity

**Solution:**
```bash
# Check OVN pod resources
oc get pods -n openshift-ovn-kubernetes -o yaml | grep -A 5 resources

# Scale down test
./generate-customer-scale-pods.sh --clean

# Start with smaller scale
./generate-customer-scale-pods.sh --total-pods 100 --policy-count 10 --apply
```

### Issue: Slow policy application

**Cause:** Network congestion or controller throttling

**Solution:**
```bash
# Check controller logs
oc logs -n openshift-ovn-kubernetes -l app=ovnkube-master -c ovnkube-controller

# Monitor ACL creation rate
watch -n 5 './demo-acl-check.sh'

# Consider increasing delay between policy applications
# Edit script: change sleep 10 to sleep 20
```

### Issue: "No running ovnkube pods found"

**Solution:**
```bash
# Check OVN deployment
oc get deployment -n openshift-ovn-kubernetes

# Check daemonset
oc get daemonset -n openshift-ovn-kubernetes

# Verify network operator
oc get network.operator.openshift.io cluster -o yaml
```

---

## Cleanup

### Clean Specific Test

```bash
# Pods-based test (all resources)
./clean-customer-scale-pods.sh

# Pods-based test (deployments only, keep policies/NADs)
./clean-customer-scale-pods.sh --deployments-only

# Preview what would be deleted (dry run)
./clean-customer-scale-pods.sh --dry-run

# VM-based test (customer-scale)
./generate-customer-scale-vms.sh --clean

# VM-based test (simplified)
./generate-vms-with-mnp.sh --clean

# Legacy cleanup using generate script
./generate-customer-scale-pods.sh --clean
```

### Manual Cleanup

```bash
# Delete namespace (removes everything)
oc delete namespace loadtest

# Delete specific resources
oc delete multinetworkpolicies -n loadtest -l test=customer-scale
oc delete deployment -n loadtest -l test=customer-scale
oc delete vm -n loadtest -l test=customer-scale
oc delete net-attach-def -n loadtest

# Remove generated files
rm -rf generated-customer-scale-pods/
rm -rf generated-customer-scale-vms/
rm -rf generated-vms-mnp/
```

### Partial Cleanup During Testing

```bash
# Remove only deployments (for quick iteration on pod tests)
./clean-customer-scale-pods.sh --deployments-only

# Remove only policies (keep deployments and NADs)
./clean-customer-scale-pods.sh --skip-deployments --skip-nads

# Remove everything except NADs (reuse network configuration)
./clean-customer-scale-pods.sh --skip-nads
```

---

## Best Practices

### 1. Use Gradual Mode for Large Deployments (RECOMMENDED)

```bash
# For 500+ pods, ALWAYS use gradual mode
./generate-customer-scale-pods.sh \
  --deployment-count 100 \
  --replicas 10 \
  --gradual \
  --step-size 10 \
  --step-interval 30 \
  --apply

# Benefits:
# - Prevents cluster overload
# - Better monitoring and debugging
# - Can interrupt if issues arise
```

### 2. Start Small, Scale Gradually

```bash
# Progressive scaling approach
./generate-customer-scale-pods.sh --total-pods 10 --policy-count 5 --apply
# Observe cluster behavior, then scale up

# Use deployments-only mode to add more pods incrementally
./generate-customer-scale-pods.sh \
  --deployment-count 50 \
  --replicas 10 \
  --deployments-only \
  --gradual \
  --apply
```

### 3. Monitor Resource Usage

```bash
# Before starting large test
oc adm top nodes
oc adm top pods -n openshift-ovn-kubernetes

# During test (in separate terminal)
watch -n 30 'oc adm top nodes'

# Monitor ACL generation during gradual deployment
watch -n 30 './demo-acl-check.sh'
```

### 4. Use Dry-Run First

```bash
# Validate before applying
./generate-customer-scale-pods.sh \
  --deployment-count 100 \
  --replicas 10 \
  --gradual \
  --dry-run

# Review generated files
cat generated-customer-scale-pods/SUMMARY.md
```

### 5. Save Logs

```bash
# Capture full deployment log with timestamp
./generate-customer-scale-pods.sh \
  --deployment-count 100 \
  --replicas 10 \
  --gradual \
  --step-size 10 \
  --apply 2>&1 | tee deployment-$(date +%Y%m%d-%H%M%S).log
```

### 6. Baseline Before Load Testing

```bash
# Capture baseline ACL count
./demo-acl-check.sh > baseline-acls.txt

# Run test
./generate-customer-scale-pods.sh --gradual --apply

# Compare after
./demo-acl-check.sh > after-acls.txt
diff baseline-acls.txt after-acls.txt
```

### 7. Use Deployments-Only for Incremental Testing

```bash
# Setup base environment once (NADs + policies)
./generate-customer-scale-pods.sh \
  --deployment-count 10 \
  --policy-count 385 \
  --apply

# Add more pods without recreating policies
./generate-customer-scale-pods.sh \
  --deployment-count 50 \
  --deployments-only \
  --gradual \
  --apply
```

---

## Advanced Usage

### Custom CIDR Counts

```bash
# Test with different CIDR densities
./generate-customer-scale-pods.sh \
  --total-pods 100 \
  --policy-count 10 \
  --cidrs-per-policy 100 \  # Lower CIDR count
  --apply

./generate-customer-scale-pods.sh \
  --total-pods 100 \
  --policy-count 10 \
  --cidrs-per-policy 1000 \  # Higher CIDR count
  --apply
```

### Custom VLAN Count

```bash
# Test with more VLANs
./generate-customer-scale-pods.sh \
  --total-pods 100 \
  --vlan-count 15 \  # More VLANs
  --policy-count 10 \
  --apply
```

### Different Namespaces

```bash
# Test in different namespace
./generate-customer-scale-pods.sh \
  --namespace my-test \
  --total-pods 100 \
  --policy-count 10 \
  --apply
```

---

## References

### Documentation
- **Gradual Deployment Guide:** See [GRADUAL_DEPLOYMENT_GUIDE.md](./GRADUAL_DEPLOYMENT_GUIDE.md) for detailed gradual deployment usage
- **Dependencies:** See [DEPENDENCIES.md](./DEPENDENCIES.md) for detailed dependency information

### External Links
- **OpenShift Networking:** https://docs.openshift.com/container-platform/latest/networking/
- **MultiNetworkPolicy:** https://docs.openshift.com/container-platform/latest/networking/multiple_networks/
- **OVN-Kubernetes:** https://github.com/ovn-org/ovn-kubernetes

---

## Support

For issues or questions:

1. Check logs: `./demo-acl-check.sh` and cluster logs
2. Review generated SUMMARY.md files for deployment details
3. Consult DEPENDENCIES.md for tool requirements
4. File issues with deployment logs and ACL counts

---

**Last Updated:** March 2026
**Tested On:** OpenShift 4.15 with OVN-Kubernetes

## New Features (March 2026)

- ✨ **Gradual Deployment Mode** - Apply pods in steps to prevent cluster overload
- ✨ **Deployments-Only Mode** - Add pods without recreating NADs/policies
- ✨ **Enhanced Cleanup Script** - Flexible cleanup with selective deletion options
- 📚 **Comprehensive Guide** - See [GRADUAL_DEPLOYMENT_GUIDE.md](./GRADUAL_DEPLOYMENT_GUIDE.md) for detailed examples
