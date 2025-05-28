#!/bin/bash

set -euo pipefail

: "${NAMESPACE:?Please export NAMESPACE before running this script}"

echo "📦 Fetching output files from PVC..."

kubectl cp "${NAMESPACE}/pvc-uploader:workspace/report.html" ./report.html
kubectl cp "${NAMESPACE}/pvc-uploader:workspace/timeline.html" ./timeline.html
kubectl cp "${NAMESPACE}/pvc-uploader:workspace/trace.txt" ./trace.txt

echo "✅ Output files copied:"
echo " - report.html"
echo " - timeline.html"
echo " - trace.txt"

# Optional: open in browser
if command -v open &>/dev/null; then
  echo "🌐 Opening report.html and timeline.html in default browser (macOS)..."
  open report.html
  open timeline.html
elif command -v xdg-open &>/dev/null; then
  echo "🌐 Opening report.html and timeline.html in default browser (Linux)..."
  xdg-open report.html
  xdg-open timeline.html
elif command -v wslview &>/dev/null; then
  echo "🌐 Opening report.html and timeline.html in default browser (WSL)..."
  wslview report.html
  wslview timeline.html
else
  echo "ℹ️ Output files copied. Please open them manually in your browser:"
  echo "    file://$(pwd)/report.html"
  echo "    file://$(pwd)/timeline.html"
fi

