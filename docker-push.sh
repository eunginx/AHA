#!/bin/bash
# docker-push.sh - Build, tag, and push the Obsidian solution to a private Docker Hub repo
# Usage: ./docker-push.sh <dockerhub-username> <repo-name> [tag]

set -euo pipefail

DOCKERHUB_USER="${1:-}"
REPO_NAME="${2:-obsidian-private}"
TAG="${3:-latest}"
FULL_IMAGE="${DOCKERHUB_USER}/${REPO_NAME}:${TAG}"

if [[ -z "$DOCKERHUB_USER" ]]; then
    echo "Usage: $0 <dockerhub-username> <repo-name> [tag]"
    echo "Example: $0 myuser obsidian-private latest"
    exit 1
fi

echo "========================================"
echo "Docker Hub Private Repo Push"
echo "Image: ${FULL_IMAGE}"
echo "========================================"

# Check if already logged in to Docker Hub
if ! docker info 2>/dev/null | grep -q "Username: ${DOCKERHUB_USER}"; then
    echo "Docker Hub login required ..."
    docker login
else
    echo "Already logged in to Docker Hub as ${DOCKERHUB_USER}"
fi

# Option 1: Build from Dockerfile
echo ""
echo "--- Building image from Dockerfile ---"
docker build -t "${FULL_IMAGE}" .

# Option 2: (Uncomment if you prefer to commit the RUNNING container instead)
# echo "--- Committing running obsidian container ---"
# docker commit obsidian "${FULL_IMAGE}"

echo ""
echo "--- Pushing ${FULL_IMAGE} to Docker Hub ---"
docker push "${FULL_IMAGE}"

echo ""
echo "--- Pushing completed successfully ---"
echo "Private image: ${FULL_IMAGE}"
echo ""
echo "To use this image, update your .env:"
echo "  OBSIDIAN_IMAGE=${FULL_IMAGE}"
