#!/bin/bash

set -euo pipefail

# Check that NAMESPACE is set
: "${NAMESPACE:?You must export NAMESPACE before running this script}"

echo "🔍 Listing contents of /workspace in pod pvc-uploader (namespace: $NAMESPACE)..."

kubectl exec -n "$NAMESPACE" pvc-uploader -- ls -lah /workspace

