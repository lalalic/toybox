#!/bin/bash
# Helper to call Toybox AppAgent MCP
# Usage: ./mcp.sh snapshot | ./mcp.sh tap r3 | ./mcp.sh screenshot

DEVICE_IP="[fd23:dcd5:a8c0::1]"
PORT=9223
MCP_URL="http://${DEVICE_IP}:${PORT}/mcp"

CMD="${1:-snapshot}"
shift

# Build args JSON
case "$CMD" in
  snapshot)
    ARGS='{"command":"snapshot"}'
    ;;
  tap)
    ARGS="{\"command\":\"tap\",\"ref\":\"$1\"}"
    ;;
  type)
    ARGS="{\"command\":\"type\",\"ref\":\"$1\",\"text\":\"$2\"}"
    ;;
  find)
    ARGS="{\"command\":\"find\",\"text\":\"$1\"}"
    ;;
  screenshot)
    ARGS='{"command":"screenshot"}'
    ;;
  swipe)
    ARGS="{\"command\":\"swipe\",\"direction\":\"$1\"}"
    ;;
  *)
    echo "Usage: $0 {snapshot|tap|type|find|screenshot|swipe} [args...]"
    exit 1
    ;;
esac

curl -s -X POST "$MCP_URL" \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"app_agent\",\"arguments\":$ARGS}}" \
  | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('result',{}).get('content',[{}])[0].get('text','no response'))" 2>/dev/null
