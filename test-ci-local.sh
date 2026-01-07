#!/bin/bash
# Script om de CI workflow lokaal te testen
# Run dit vanuit de obscura_infrastructure directory

echo "=== Starting local CI test ==="

# Controleer of we in de juiste directory zitten
if [ ! -f "docker-compose.yml" ]; then
    echo "Error: docker-compose.yml not found. Run this from obscura_infrastructure directory"
    exit 1
fi

# Controleer of backend en frontend directories bestaan
if [ ! -d "../obscura_backend" ]; then
    echo "Error: obscura_backend directory not found"
    exit 1
fi

if [ ! -d "../obscura_frontend" ]; then
    echo "Error: obscura_frontend directory not found"
    exit 1
fi

# 1. Build Docker images
echo "=== Building Docker images ==="
docker build -t obscura-backend ../obscura_backend || exit 1
docker build -t obscura-frontend ../obscura_frontend || exit 1

# 2. Run backend tests (met PostgreSQL)
echo "=== Running backend tests ==="
cd ../obscura_backend
docker run --rm \
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://host.docker.internal:5432/obscura_test \
  -e SPRING_DATASOURCE_USERNAME=test \
  -e SPRING_DATASOURCE_PASSWORD=test \
  -e PHOTO_UPLOAD_DIR=/tmp/uploads \
  obscura-backend ./gradlew test --no-daemon || exit 1

cd ../obscura_infrastructure

# 3. Start full stack met Docker Compose
echo "=== Starting Docker Compose stack ==="
docker-compose up -d || exit 1

# 4. Wait for services
echo "=== Waiting for services to be ready ==="
sleep 30

# Check backend health
echo "Checking backend health..."
timeout 60 bash -c 'until curl -f http://localhost:8080/actuator/health; do echo "Waiting for backend..."; sleep 2; done' || exit 1

# Check frontend
echo "Checking frontend..."
timeout 60 bash -c 'until curl -f http://localhost:3000; do echo "Waiting for frontend..."; sleep 2; done' || exit 1

# 5. Run Playwright tests
echo "=== Running Playwright e2e tests ==="
cd ../obscura_frontend
npm install || exit 1
npx playwright install --with-deps || exit 1
npx playwright test || exit 1

cd ../obscura_infrastructure

# 6. Cleanup
echo "=== Stopping Docker Compose ==="
docker-compose down

echo "=== All tests passed! ==="

