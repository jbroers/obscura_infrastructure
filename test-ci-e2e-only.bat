@echo off
REM Simplified CI test script - skips backend unit tests, only tests e2e
REM Run dit vanuit de obscura_infrastructure directory

echo === Starting simplified CI test (E2E only) ===

REM Controleer of we in de juiste directory zitten
if not exist "docker-compose.yml" (
    echo Error: docker-compose.yml not found. Run this from obscura_infrastructure directory
    exit /b 1
)

REM 1. Build Docker images
echo === Building Docker images ===
docker build -t obscura-backend ..\obscura_backend
if errorlevel 1 exit /b 1

docker build -t obscura-frontend ..\obscura_frontend
if errorlevel 1 exit /b 1

REM 2. Start full stack met Docker Compose
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

REM 3. Wait for services
echo === Waiting for services to be ready (30 seconds) ===
timeout /t 30 /nobreak >nul

REM Check backend health
echo Checking backend health...
set /a attempts=0
:check_backend
set /a attempts+=1
if %attempts% GTR 30 (
    echo ERROR: Backend did not start in time
    docker-compose logs backend
    docker-compose down
    exit /b 1
)
curl -f http://localhost:8080/actuator/health >nul 2>&1
if errorlevel 1 (
    echo Waiting for backend... (attempt %attempts%/30)
    timeout /t 2 /nobreak >nul
    goto check_backend
)
echo Backend is ready!

REM Check frontend
echo Checking frontend...
set /a attempts=0
:check_frontend
set /a attempts+=1
if %attempts% GTR 30 (
    echo ERROR: Frontend did not start in time
    docker-compose logs frontend
    docker-compose down
    exit /b 1
)
curl -f http://localhost:3000 >nul 2>&1
if errorlevel 1 (
    echo Waiting for frontend... (attempt %attempts%/30)
    timeout /t 2 /nobreak >nul
    goto check_frontend
)
echo Frontend is ready!

REM 4. Run Playwright tests
echo === Running Playwright e2e tests ===
cd ..\obscura_frontend
call npm install
if errorlevel 1 (
    echo NPM install failed
    cd ..\obscura_infrastructure
    docker-compose down
    exit /b 1
)

echo Installing Playwright browsers...
call npx playwright install --with-deps
if errorlevel 1 (
    echo Playwright install failed
    cd ..\obscura_infrastructure
    docker-compose down
    exit /b 1
)

echo Running Playwright tests...
call npx playwright test
if errorlevel 1 (
    echo Playwright tests failed! Check playwright-report/
    echo Opening report...
    call npx playwright show-report
    cd ..\obscura_infrastructure
    docker-compose down
    exit /b 1
)

cd ..\obscura_infrastructure

REM 5. Cleanup
echo === Stopping Docker Compose ===
docker-compose down

echo.
echo ============================================
echo === All E2E tests passed! ===
echo ============================================
echo.
echo Stack tested:
echo   - Backend (Spring Boot): http://localhost:8080
echo   - Frontend (Next.js): http://localhost:3000
echo   - Database (PostgreSQL): localhost:5432
echo   - Playwright E2E tests: PASSED
echo.

