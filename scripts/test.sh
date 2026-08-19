#!/usr/bin/env sh

# Exit immediately if any command fails
set -e

echo "======================================"
echo "Starting Full Stack Test"
echo "======================================"

# Generate Docker Compose configuration
echo "Generating docker-stack.yml..."

DOMAIN=backend \
SMTP_HOST="" \
TRAEFIK_PUBLIC_NETWORK_IS_EXTERNAL=false \
TRAEFIK_PUBLIC_NETWORK=traefik-public \
INSTALL_DEV=true \
docker compose \
  -f docker-compose.yml \
  config > docker-stack.yml

echo "Docker Compose configuration generated."

# Build application images
echo "======================================"
echo "Building Docker images..."
echo "======================================"

docker compose -f docker-stack.yml build

# Remove old containers
echo "======================================"
echo "Removing old containers..."
echo "======================================"

docker compose -f docker-stack.yml down -v --remove-orphans

# Start all required services
echo "======================================"
echo "Starting Docker services..."
echo "======================================"

docker compose -f docker-stack.yml up -d

# Show running containers
echo "======================================"
echo "Docker containers:"
echo "======================================"

docker compose -f docker-stack.yml ps

# Wait for MongoDB
echo "======================================"
echo "Waiting for MongoDB..."
echo "======================================"

i=1

while [ "$i" -le 30 ]; do
    if docker compose -f docker-stack.yml exec -T mongodb \
        mongosh --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
        echo "MongoDB is ready."
        break
    fi

    echo "MongoDB is not ready yet. Attempt $i/30..."
    sleep 2
    i=$((i + 1))
done

if [ "$i" -gt 30 ]; then
    echo "ERROR: MongoDB did not become ready."

    echo "MongoDB logs:"
    docker compose -f docker-stack.yml logs mongodb

    echo "Backend logs:"
    docker compose -f docker-stack.yml logs backend

    docker compose -f docker-stack.yml down -v --remove-orphans
    exit 1
fi

# Wait for backend
echo "======================================"
echo "Waiting for backend..."
echo "======================================"

sleep 5

echo "Backend logs:"
docker compose -f docker-stack.yml logs --tail=50 backend

# Run application tests
echo "======================================"
echo "Running backend tests..."
echo "======================================"

docker compose -f docker-stack.yml exec -T backend \
    bash /app/tests-start.sh "$@"

TEST_EXIT_CODE=$?

# Show final logs if tests failed
if [ "$TEST_EXIT_CODE" -ne 0 ]; then
    echo "======================================"
    echo "Tests failed."
    echo "======================================"

    echo "MongoDB logs:"
    docker compose -f docker-stack.yml logs --tail=100 mongodb

    echo "Backend logs:"
    docker compose -f docker-stack.yml logs --tail=100 backend
fi

# Cleanup
echo "======================================"
echo "Cleaning up..."
echo "======================================"

docker compose -f docker-stack.yml down -v --remove-orphans

echo "======================================"
echo "Test completed."
echo "======================================"

exit "$TEST_EXIT_CODE"
