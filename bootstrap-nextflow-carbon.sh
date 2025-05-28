#!/bin/bash

set -euo pipefail

: "${NAMESPACE:?You must export NAMESPACE before running this script}"

echo "[INFO] Using namespace: $NAMESPACE"

PVC_NAME="nextflow-pvc"
STORAGE_CLASS="cephfs"
PVC_FILE="nextflow-pvc.yaml"
UPLOADER_FILE="pvc-uploader.yaml"

echo "🔧 Creating namespace: $NAMESPACE (if not exists)"
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"

echo "💾 Creating PersistentVolumeClaim: $PVC_NAME"
envsubst < "$PVC_FILE" | kubectl apply -f -

echo "📦 Deploying uploader pod (manual data injector)"
envsubst < "$UPLOADER_FILE" | kubectl apply -f -

echo "✅ All resources created successfully!"
echo "👉 You can now monitor jobs via: kubectl get jobs -n $NAMESPACE"

