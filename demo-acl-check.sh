#!/bin/bash

POD=$(oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-node --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')

echo "=========================================="
echo "OVN ACL Count Check"
echo "=========================================="
echo "Using pod: $POD"
echo ""

echo "=== Total ACL Count ==="
TOTAL=$(oc exec -n openshift-ovn-kubernetes $POD -c ovnkube-controller -- ovn-nbctl list ACL 2>/dev/null | grep "^_uuid" | wc -l)
echo "Total ACLs: $TOTAL"
echo ""

echo "=== ACLs by Direction ==="
INGRESS=$(oc exec -n openshift-ovn-kubernetes $POD -c ovnkube-controller -- ovn-nbctl --columns=direction list ACL 2>/dev/null | grep "from-lport" | wc -l)
EGRESS=$(oc exec -n openshift-ovn-kubernetes $POD -c ovnkube-controller -- ovn-nbctl --columns=direction list ACL 2>/dev/null | grep "to-lport" | wc -l)
echo "Ingress ACLs (from-lport): $INGRESS"
echo "Egress ACLs (to-lport): $EGRESS"
echo ""

echo "=== Top 5 ACL Priorities ==="
oc exec -n openshift-ovn-kubernetes $POD -c ovnkube-controller -- ovn-nbctl --columns=priority list ACL 2>/dev/null | \
  grep "^priority" | awk '{print $3}' | sort | uniq -c | sort -rn | head -5 | \
  awk '{printf "Priority %5d: %3d ACLs\n", $2, $1}'
