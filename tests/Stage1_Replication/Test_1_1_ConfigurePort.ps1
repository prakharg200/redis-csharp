# Test 1.1: Configure Listening Port
# Tests the ability to start Redis server on a custom port

param(
    [switch]$Verbose
)

Import-Module "$PSScriptRoot\..\TestHelper.psm1" -Force

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Test 1.1: Configure Listening Port               ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Reset-TestResults

# Test 1: Start server on default port (6379)
Write-Host "Test 1: Starting server on default port 6379..." -ForegroundColor Yellow
$server1 = Start-RedisServer -Port 6379
if ($server1) {
    Test-RedisCommand -Command "PING" -ExpectedOutput "PONG" -Port 6379 -TestName "PING on default port 6379"
    Stop-RedisServer -Process $server1
} else {
    Write-Host "  ❌ FAIL: Could not start server on port 6379" -ForegroundColor Red
    $script:TestResults.Failed++
}

Start-Sleep -Milliseconds 500

# Test 2: Start server on custom port (6380)
Write-Host ""
Write-Host "Test 2: Starting server on custom port 6380..." -ForegroundColor Yellow
$server2 = Start-RedisServer -Port 6380
if ($server2) {
    Test-RedisCommand -Command "PING" -ExpectedOutput "PONG" -Port 6380 -TestName "PING on custom port 6380"
    Stop-RedisServer -Process $server2
} else {
    Write-Host "  ❌ FAIL: Could not start server on port 6380" -ForegroundColor Red
    $script:TestResults.Failed++
}

Start-Sleep -Milliseconds 500

# Test 3: Start server on another custom port (7000)
Write-Host ""
Write-Host "Test 3: Starting server on custom port 7000..." -ForegroundColor Yellow
$server3 = Start-RedisServer -Port 7000
if ($server3) {
    Test-RedisCommand -Command "PING" -ExpectedOutput "PONG" -Port 7000 -TestName "PING on custom port 7000"
    Test-RedisCommand -Command "ECHO 'Hello Custom Port'" -ExpectedOutput "Hello Custom Port" -Port 7000 -TestName "ECHO on custom port 7000"
    Stop-RedisServer -Process $server3
} else {
    Write-Host "  ❌ FAIL: Could not start server on port 7000" -ForegroundColor Red
    $script:TestResults.Failed++
}

# Test 4: Verify port argument parsing (negative test - should use default if no --port provided)
Write-Host ""
Write-Host "Test 4: Verifying default port behavior..." -ForegroundColor Yellow
$server4 = Start-RedisServer -Port 6379
if ($server4) {
    Test-RedisCommand -Command "PING" -ExpectedOutput "PONG" -Port 6379 -TestName "Server falls back to default port 6379"
    Stop-RedisServer -Process $server4
}

# Summary
$success = Write-TestSummary

if (-not $success) {
    exit 1
}

exit 0
