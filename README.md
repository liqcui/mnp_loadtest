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

### Quick Test (VMs - 10 VMs, 5 policies)

```bash
./generate-vms-with-mnp.sh --total-vms 10 --policy-count 5 --apply
```

## Main Scripts

### 1. generate-customer-scale-pods.sh

**Purpose:** Generate customer-scale deployment with Pods/Deployments and CIDR-heavy MultiNetworkPolicies

**Use Case:** Testing Pod-based workloads with realistic customer patterns

```bash
# Small test (10 Pods × 10 replicas, 5 policies)
./generate-customer-scale-pods.sh \
  --total-pods 100 \
  --policy-count 5 \
  --cidrs-per-policy 450 \
  --apply

# Medium test (50 Pods × 10 replicas, 25 policies)
./generate-customer-scale-pods.sh \
  --total-pods 500 \
  --policy-count 25 \
  --apply

# Full scale (1000 Pods via 100 deployments × 10 replicas, 385 policies)
# WARNING: Requires large cluster (5+ worker nodes, 32GB+ RAM per node)
./generate-customer-scale-pods.sh \
  --total-pods 1000 \
  --policy-count 385 \
  --cidrs-per-policy 450 \
  --apply
```

**Key Features:**
- Creates **100 Deployments** with **10 replicas each** = 1000 total pods
- Generates **385 CIDR-heavy policies** (450 CIDRs × 2 ports each)
- Expected ACL count: **~346,000 ACLs** for full scale
- Applies policies with **10-second delays** between each for controlled rollout
- Uses realistic policy names matching customer patterns
- Supports dry-run mode for validation

**Output Structure:**
```
generated-customer-scale-pods/
├── networks/                          # NetworkAttachmentDefinitions
│   └── nad-vlan{750-758}.yaml         # 9 VLAN definitions
├── pods/                              # Deployment manifests
│   └── loadtest-pod-{0-99}.yaml       # 100 deployments (10 replicas each)
├── policies/                          # MultiNetworkPolicy manifests
│   └── {policy-name}.yaml             # 385 policy files
├── all-in-one.yaml                    # Combined manifest
└── SUMMARY.md                         # Deployment summary
```

**Configuration Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--total-pods` | 10 | Total pods (will create deployments = pods/10) |
| `--policy-count` | 485 | Number of MultiNetworkPolicies |
| `--cidrs-per-policy` | 450 | CIDR blocks per policy |
| `--vlan-count` | 9 | Number of VLANs (vlan750-vlan758) |
| `--namespace` | loadtest | Target namespace |
| `--dry-run` | false | Generate files without applying |
| `--apply` | false | Apply to cluster |
| `--clean` | - | Clean up all resources |

**Expected Results:**

| Scale | Deployments | Total Pods | Policies | Expected ACLs | Time to Deploy |
|-------|-------------|------------|----------|---------------|----------------|
| Small | 10 | 100 | 5 | ~4,500 | ~2 min |
| Medium | 50 | 500 | 25 | ~22,500 | ~8 min |
| Full | 100 | 1,000 | 385 | ~346,000 | ~17 min |

---

### 2. generate-customer-scale.sh

**Purpose:** Generate customer-scale VirtualMachines with CIDR-heavy MultiNetworkPolicies

**Use Case:** Testing VM-based workloads (requires OpenShift Virtualization/KubeVirt)

```bash
# Small test (10 VMs, proportional policies)
./generate-customer-scale.sh \
  --total-vms 10 \
  --policy-count 5 \
  --apply

# Medium test (50 VMs, ~25 policies)
./generate-customer-scale.sh \
  --total-vms 50 \
  --policy-count 25 \
  --apply

# Large test (100 VMs, full customer pattern)
./generate-customer-scale.sh \
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
generated-customer-scale/
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
- Similar to `generate-customer-scale.sh` but with simpler configuration
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

### Example 1: Full Pod-Based Customer Simulation

```bash
# 1. Generate and apply resources (1000 pods, 385 policies)
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
./generate-customer-scale-pods.sh --clean
```

### Example 2: Progressive Load Testing (Pods)

```bash
# Start small
./generate-customer-scale-pods.sh --total-pods 100 --policy-count 5 --apply
./demo-acl-check.sh
# Wait and observe cluster

# Scale to medium
./generate-customer-scale-pods.sh --clean
./generate-customer-scale-pods.sh --total-pods 500 --policy-count 25 --apply
./demo-acl-check.sh
# Wait and observe cluster

# Scale to full
./generate-customer-scale-pods.sh --clean
./generate-customer-scale-pods.sh --total-pods 1000 --policy-count 385 --apply
./demo-acl-check.sh
```

### Example 3: VM-Based Testing

```bash
# 1. Verify KubeVirt is installed
oc get csv -n openshift-cnv | grep kubevirt

# 2. Generate VM-based deployment
./generate-customer-scale.sh \
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
./generate-customer-scale.sh --clean
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

### Issue: Pods stuck in ContainerCreating

**Cause:** Secondary network not ready

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
# Pods-based test
./generate-customer-scale-pods.sh --clean

# VM-based test (customer-scale)
./generate-customer-scale.sh --clean

# VM-based test (simplified)
./generate-vms-with-mnp.sh --clean
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
rm -rf generated-customer-scale/
rm -rf generated-vms-mnp/
```

---

## Best Practices

### 1. Start Small, Scale Gradually

```bash
# Progressive scaling approach
./generate-customer-scale-pods.sh --total-pods 10 --policy-count 5 --apply
# Observe cluster behavior, then scale up
```

### 2. Monitor Resource Usage

```bash
# Before starting large test
oc adm top nodes
oc adm top pods -n openshift-ovn-kubernetes

# During test
watch -n 30 'oc adm top nodes'
```

### 3. Use Dry-Run First

```bash
# Validate before applying
./generate-customer-scale-pods.sh --total-pods 1000 --policy-count 385 --dry-run

# Review generated files
cat generated-customer-scale-pods/SUMMARY.md
```

### 4. Save Logs

```bash
# Capture full deployment log
./generate-customer-scale-pods.sh --total-pods 1000 --policy-count 385 --apply \
  2>&1 | tee deployment-$(date +%Y%m%d-%H%M%S).log
```

### 5. Baseline Before Load Testing

```bash
# Capture baseline ACL count
./demo-acl-check.sh > baseline-acls.txt

# Run test
./generate-customer-scale-pods.sh --apply

# Compare after
./demo-acl-check.sh > after-acls.txt
diff baseline-acls.txt after-acls.txt
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

- **Dependencies:** See [DEPENDENCIES.md](./DEPENDENCIES.md) for detailed dependency information
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

**Last Updated:** February 2026  
**Tested On:** OpenShift 4.15 with OVN-Kubernetes
