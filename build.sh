#!/bin/bash
set -euo pipefail

IMAGE="${IMAGE:-cf-ddns:latest}"

# Always build for linux/amd64 (x86_64 target host)
docker buildx build \
  --platform linux/amd64 \
  --load \
  -t "$IMAGE" \
  .

echo "Built $IMAGE (linux/amd64)"
