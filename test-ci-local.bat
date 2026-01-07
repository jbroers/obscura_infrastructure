@echo off
REM Script om de CI workflow lokaal te testen op Windows
REM Run dit vanuit de obscura_infrastructure directory

echo === Starting local CI test ===

REM Controleer of we in de juiste directory zitten
if not exist "docker-compose.yml" (
    echo Error: docker-compose.yml not found. Run this from obscura_infrastructure directory
    exit /b 1
)

REM Controleer of backend en frontend directories bestaan
if not exist "..\obscura_backend" (
    echo Error: obscura_backend directory not found
    exit /b 1
)

if not exist "..\obscura_frontend" (
    echo Error: obscura_frontend directory not found
    exit /b 1
)

REM 1. Build Docker images
echo === Building Docker images ===
docker build -t obscura-backend ..\obscura_backend
if errorlevel 1 exit /b 1

docker build -t obscura-frontend ..\obscura_frontend
if errorlevel 1 exit /b 1

REM 2. Start PostgreSQL voor tests (als die nog niet draait)
echo === Ensuring PostgreSQL is running ===
docker run -d --name postgres-test -e POSTGRES_USER=test -e POSTGRES_PASSWORD=test -e POSTGRES_DB=obscura_test -p 5432:5432 postgres:15 2>nul
timeout /t 10 /nobreak >nul

REM 3. Run backend tests
echo === Running backend tests ===
cd ..\obscura_backend

REM Create uploads directory if it doesn't exist
if not exist "C:\temp\uploads" mkdir "C:\temp\uploads"

call gradlew.bat test --no-daemon -Dspring.profiles.active=test
if errorlevel 1 (
    echo Backend tests failed! Check build/reports/tests/test/index.html
    cd ..\obscura_infrastructure
    docker stop postgres-test 2>nul
    docker rm postgres-test 2>nul
    exit /b 1
)
cd ..\obscura_infrastructure

REM Stop test PostgreSQL before starting Docker Compose
echo === Stopping test PostgreSQL ===
docker stop postgres-test 2>nul
docker rm postgres-test 2>nul

REM 4. Start full stack met Docker Compose
echo === Starting Docker Compose stack ===
REM Set environment variables for Docker Compose
set SPRING_DATASOURCE_URL=jdbc:postgresql://db:5432/obscura
set SPRING_DATASOURCE_USERNAME=obscura_user
set SPRING_DATASOURCE_PASSWORD=obscura_pass
set DB_NAME=obscura
set SPRING_PROFILES_ACTIVE=prod
set PHOTO_UPLOAD_DIR=/uploads
set BACKEND_URL=http://localhost:8080

docker-compose up -d
if errorlevel 1 exit /b 1

REM 5. Wait for services
echo === Waiting for services to be ready (30 seconds) ===
timeout /t 30 /nobreak >nul

REM Check backend health
echo Checking backend health...
:check_backend
curl -f http://localhost:8080/actuator/health >nul 2>&1
if errorlevel 1 (
    echo Waiting for backend...
    timeout /t 2 /nobreak >nul
    goto check_backend
)

REM Check frontend
echo Checking frontend...
:check_frontend
curl -f http://localhost:3000 >nul 2>&1
if errorlevel 1 (
    echo Waiting for frontend...
    timeout /t 2 /nobreak >nul
    goto check_frontend
)

REM 6. Run Playwright tests
echo === Running Playwright e2e tests ===
cd ..\obscura_frontend
call npm install
if errorlevel 1 (
    cd ..\obscura_infrastructure
    docker-compose down
    exit /b 1
)

call npx playwright install --with-deps
if errorlevel 1 (
    cd ..\obscura_infrastructure
    docker-compose down
    exit /b 1
)

call npx playwright test
if errorlevel 1 (
    cd ..\obscura_infrastructure
    docker-compose down
    exit /b 1
)

cd ..\obscura_infrastructure

REM 7. Cleanup
echo === Stopping Docker Compose ===
docker-compose down

echo === Cleaning up test PostgreSQL ===
docker stop postgres-test 2>nul
docker rm postgres-test 2>nul

echo === All tests passed! ===

