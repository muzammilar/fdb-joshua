#!/bin/bash
# joshua-failures.sh - View Joshua test failure details
# Usage: joshua-failures.sh --context <context> <ensemble_id> [--max <n>] [--rhel9]

CONTEXT="${JOSHUA_CONTEXT:-}"
SCALER_TYPE="regular"
MAX_FAILURES=5
ENSEMBLE_ID=""

# Parse named arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --context|-c)
            CONTEXT="$2"
            shift 2
            ;;
        --max|-m)
            MAX_FAILURES="$2"
            shift 2
            ;;
        --rhel9)
            SCALER_TYPE="rhel9"
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            ENSEMBLE_ID="$1"
            shift
            ;;
    esac
done

if [ -z "$CONTEXT" ]; then
    echo "Error: --context is required (or set JOSHUA_CONTEXT env var)"
    echo "Usage: $0 --context <k8s-context> <ensemble_id> [--max <n>] [--rhel9]"
    exit 1
fi

if [ -z "$ENSEMBLE_ID" ]; then
    echo "Error: ensemble_id is required"
    echo "Usage: $0 --context <k8s-context> <ensemble_id> [--max <n>] [--rhel9]"
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

echo "Using scaler pod: $SCALER_POD"

kubectl --context "$CONTEXT" exec -it "$SCALER_POD" -- python3 -c "
import sys; sys.path.append('/tools')
import joshua_model

joshua_model.open('/etc/foundationdb/fdb.cluster')

ensemble_id = '$ENSEMBLE_ID'
max_failures = $MAX_FAILURES

# Get ensemble properties for summary
props = joshua_model.get_ensemble_properties(ensemble_id)

print('=' * 60)
print(f'ENSEMBLE: {ensemble_id}')
print('=' * 60)

passed = props.get('pass', 0)
failed = props.get('fail', 0)
max_runs = props.get('max_runs', 0)
total = passed + failed

print(f'')
print(f'=== JOB RUN SUMMARY ===')
print(f'  Passed:      {passed}')
print(f'  Failed:      {failed}')
print(f'  Total:       {total}')
print(f'  Max Runs:    {max_runs}')
if total > 0:
    print(f'  Pass Rate:   {(passed/total)*100:.2f}%')
    print(f'  Fail Rate:   {(failed/total)*100:.2f}%')
print(f'')

# Show other properties if present
skip_keys = {'pass', 'fail', 'max_runs'}
other_props = {k: v for k, v in props.items() if k not in skip_keys}
if other_props:
    print(f'=== OTHER PROPERTIES ===')
    for k, v in sorted(other_props.items()):
        print(f'  {k}: {v}')
    print(f'')

print(f'=== FAILURE DETAILS (showing up to {max_failures}) ===')
count = 0
for result in joshua_model.tail_results(ensemble_id, errors_only=True):
    count += 1
    print(f'')
    print(f'--- Failure {count} ---')
    print(result)
    if count >= max_failures:
        break

if count == 0:
    print('No failure details found')
elif count < failed:
    print(f'')
    print(f'... and {failed - count} more failures')
"
