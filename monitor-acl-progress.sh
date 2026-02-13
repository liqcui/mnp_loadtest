#!/bin/bash
#
# Monitor ACL Generation Progress
#

LOG_FILE="/Users/liqcui/customer-bugs/multi-networkpolicy/loadtest/acl-generation-large.log"
TARGET_ACLS=1574361
START_ACLS=1189

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "==========================================="
echo "ACL Generation Progress Monitor"
echo "==========================================="
echo ""
echo "Target ACLs: $TARGET_ACLS"
echo "Starting ACLs: $START_ACLS"
echo "ACLs to generate: $((TARGET_ACLS - START_ACLS))"
echo ""

# Check if process is running
if pgrep -f "generate-ovn-acls.sh --acl-count 1574361" > /dev/null; then
    echo -e "${GREEN}Status: RUNNING${NC}"
else
    echo -e "${YELLOW}Status: NOT RUNNING (may have completed or failed)${NC}"
fi
echo ""

# Get current count
echo "Checking current ACL count..."
CURRENT_COUNT=$(cd /Users/liqcui/customer-bugs/multi-networkpolicy/loadtest && ./generate-ovn-acls.sh --count-only 2>/dev/null | grep "Total ACLs" | grep -o '[0-9]*' | tail -1)

if [[ -n "$CURRENT_COUNT" ]]; then
    ADDED=$((CURRENT_COUNT - START_ACLS))
    REMAINING=$((TARGET_ACLS - ADDED))
    PERCENT=$(echo "scale=2; $ADDED * 100 / $TARGET_ACLS" | bc)
    
    echo "Current ACL count: $CURRENT_COUNT"
    echo "ACLs added: $ADDED"
    echo "Progress: ${PERCENT}%"
    echo "Remaining: $REMAINING"
    echo ""
    
    # Estimate time remaining
    if [[ -f "$LOG_FILE" ]]; then
        LAST_PROGRESS=$(tail -50 "$LOG_FILE" | grep "Progress:" | tail -1)
        echo "Last logged progress: $LAST_PROGRESS"
    fi
else
    echo "Could not determine current count"
fi

echo ""
echo "Log file: $LOG_FILE"
echo ""
echo "Commands:"
echo "  # View live progress"
echo "  tail -f $LOG_FILE"
echo ""
echo "  # Check current count"
echo "  cd /Users/liqcui/customer-bugs/multi-networkpolicy/loadtest && ./generate-ovn-acls.sh --count-only"
echo ""
echo "  # Stop generation"
echo "  pkill -f 'generate-ovn-acls.sh --acl-count 1574361'"
