#!/bin/bash

set -euo pipefail

: "${NAMESPACE:?Please export NAMESPACE before running this script}"

echo "🧹 Resetting resources in namespace: $NAMESPACE..."

# Delete Nextflow jobs (if any)
echo "🗑️  Deleting all jobs..."
kubectl delete jobs --all -n "$NAMESPACE" || true

# Clean up workspace inside pvc-uploader if it exists
echo "📁 Cleaning /workspace inside pvc-uploader pod..."
if kubectl get pod pvc-uploader -n "$NAMESPACE" &>/dev/null; then
  echo "🧼 Deleting remote /workspace contents..."
  kubectl exec -n "$NAMESPACE" pvc-uploader -- sh -c "find /workspace -mindepth 1 -delete" || echo "⚠️ Could not clean workspace"
  echo "🗑️  Deleting pvc-uploader pod"
  kubectl delete pod pvc-uploader -n "$NAMESPACE" || true
else
  echo "⚠️ pvc-uploader not found or not running, skipping workspace cleanup and pod deletion."
fi

# OPTIONAL: If you're no longer using these, it's safe to skip/delete these blocks entirely
echo "🧼 Deleting old carbon-aware ConfigMap (if any)..."
kubectl delete configmap carbon-checker-scripts -n "$NAMESPACE" || true

echo "🔐 Cleaning up RBAC roles (if previously created)..."
kubectl delete role nextflow-trigger-role -n "$NAMESPACE" || true
kubectl delete rolebinding nextflow-trigger-binding -n "$NAMESPACE" || true

# (Optional) Delete *all* pods — not usually needed unless you're debugging or in dev
 echo "🧨 Deleting ALL pods in namespace..."
 kubectl delete pods --all -n "$NAMESPACE" || true

echo "✅ Cleanup complete. You can now bootstrap again."

