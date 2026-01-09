#!/bin/bash
# joshua_remote_cli.sh - Run joshua commands against EKS cluster
# Usage: joshua_remote_cli.sh --context <context> [--joshua-dir <dir>] [--rhel9] <command> [args...]

CONTEXT="${JOSHUA_CONTEXT:-}"
JOSHUA_CHECKOUT="${JOSHUA_DIR:-$HOME/checkouts/fdb/fdb-joshua}"
SCALER_TYPE="${JOSHUA_SCALER:-regular}"

# Parse named arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --context|-c)
            CONTEXT="$2"
            shift 2
            ;;
        --joshua-dir|-j)
            JOSHUA_CHECKOUT="$2"
            shift 2
            ;;
        --rhel9)
            SCALER_TYPE="rhel9"
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [ -z "$CONTEXT" ]; then
    echo "Error: --context is required (or set JOSHUA_CONTEXT env var)"
    echo "Usage: $0 --context <k8s-context> [--joshua-dir <fdb-joshua-checkout>] [--rhel9] <command> [args...]"
    exit 1
fi

# Handle both fdb-joshua checkout dir or joshua subdir
if [ -f "$JOSHUA_CHECKOUT/joshua/joshua.py" ]; then
    JOSHUA_PY="$JOSHUA_CHECKOUT/joshua/joshua.py"
elif [ -f "$JOSHUA_CHECKOUT/joshua.py" ]; then
    JOSHUA_PY="$JOSHUA_CHECKOUT/joshua.py"
else
    echo "Error: Could not find joshua.py in $JOSHUA_CHECKOUT or $JOSHUA_CHECKOUT/joshua/"
    exit 1
fi

if [ "$SCALER_TYPE" = "rhel9" ]; then
    SCALER_POD=$(kubectl --context "$CONTEXT" get pods | grep agent-scaler | grep rhel9 | head -1 | awk '{print $1}')
else
    SCALER_POD=$(kubectl --context "$CONTEXT" get pods | grep agent-scaler | grep -v rhel9 | head -1 | awk '{print $1}')
fi

if [ -z "$SCALER_POD" ]; then
    echo "Error: Could not find agent-scaler pod (type: $SCALER_TYPE)"
    exit 1
fi

# Copy joshua.py with patched imports
sed -e 's/import lxml.etree as le/le = None/' \
    -e 's/from \. import joshua_model/import joshua_model/' \
    "$JOSHUA_PY" | \
    kubectl --context "$CONTEXT" exec -i "$SCALER_POD" -- tee /tmp/joshua.py > /dev/null

kubectl --context "$CONTEXT" exec -it "$SCALER_POD" -- env PYTHONPATH=/tools python3 /tmp/joshua.py -C /etc/foundationdb/fdb.cluster "$@"
