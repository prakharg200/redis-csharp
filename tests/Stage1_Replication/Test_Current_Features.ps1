# Test Current Features
# Tests all currently implemented features (PING, ECHO, SET, GET, RPUSH, LRANGE)

param(
    [switch]$Verbose
)

Import-Module "$PSScriptRoot\..\TestHelper.psm1" -Force

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Testing Current Implemented Features             ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Reset-TestResults

# Start server
$server = Start-RedisServer -Port 6379
if (-not $server) {
    Write-Host "❌ Failed to start Redis server" -ForegroundColor Red
    exit 1
}

try {
    # Test PING command
    Write-Host "Testing PING command..." -ForegroundColor Yellow
    Test-RedisCommand -Command "PING" -ExpectedOutput "PONG" -TestName "PING returns PONG"
    
    # Test ECHO command
    Write-Host ""
    Write-Host "Testing ECHO command..." -ForegroundColor Yellow
    Test-RedisCommand -Command "ECHO 'Hello World'" -ExpectedOutput "Hello World" -TestName "ECHO with simple string"
    Test-RedisCommand -Command "ECHO 'Redis Testing'" -ExpectedOutput "Redis Testing" -TestName "ECHO with another string"
    
    # Test SET/GET commands
    Write-Host ""
    Write-Host "Testing SET/GET commands..." -ForegroundColor Yellow
    redis-cli -p 6379 SET mykey "myvalue" | Out-Null
    Test-RedisCommand -Command "GET mykey" -ExpectedOutput "myvalue" -TestName "SET and GET simple string"
    
    redis-cli -p 6379 SET number "42" | Out-Null
    Test-RedisCommand -Command "GET number" -ExpectedOutput "42" -TestName "SET and GET number as string"
    
    # Test SET with expiry (PX)
    Write-Host ""
    Write-Host "Testing SET with expiry..." -ForegroundColor Yellow
    redis-cli -p 6379 SET tempkey "tempvalue" PX 2000 | Out-Null
    Test-RedisCommand -Command "GET tempkey" -ExpectedOutput "tempvalue" -TestName "GET key before expiry"
    
    Write-Host "  ⏳ Waiting 2.5 seconds for key to expire..." -ForegroundColor Gray
    Start-Sleep -Seconds 2.5
    
    $result = redis-cli -p 6379 GET tempkey 2>&1 | Out-String
    $result = $result.Trim()
    if ($result -eq "(nil)" -or $result -eq "") {
        Write-Host "  ✅ PASS: Key expired correctly" -ForegroundColor Green
        $Global:TestResults.Passed++
    } else {
        Write-Host "  ❌ FAIL: Key should have expired" -ForegroundColor Red
        Write-Host "     Actual: $result" -ForegroundColor Yellow
        $Global:TestResults.Failed++
    }
    
    # Test RPUSH command
    Write-Host ""
    Write-Host "Testing RPUSH command..." -ForegroundColor Yellow
    $result = redis-cli -p 6379 RPUSH mylist "item1" 2>&1 | Out-String
    $result = $result.Trim()
    if ($result -eq "(integer) 1" -or $result -eq "1") {
        Write-Host "  ✅ PASS: RPUSH returns correct count (1)" -ForegroundColor Green
        $Global:TestResults.Passed++
    } else {
        Write-Host "  ❌ FAIL: RPUSH should return 1" -ForegroundColor Red
        Write-Host "     Actual: $result" -ForegroundColor Yellow
        $Global:TestResults.Failed++
    }
    
    redis-cli -p 6379 RPUSH mylist "item2" "item3" | Out-Null
    
    # Test LRANGE command
    Write-Host ""
    Write-Host "Testing LRANGE command..." -ForegroundColor Yellow
    $result = redis-cli -p 6379 LRANGE mylist 0 -1 2>&1
    if ($result -contains "item1" -and $result -contains "item2" -and $result -contains "item3") {
        Write-Host "  ✅ PASS: LRANGE returns all items" -ForegroundColor Green
        $Global:TestResults.Passed++
    } else {
        Write-Host "  ❌ FAIL: LRANGE should return all items" -ForegroundColor Red
        Write-Host "     Actual: $($result -join ', ')" -ForegroundColor Yellow
        $Global:TestResults.Failed++
    }
    
    # Test LRANGE with specific range
    $result = redis-cli -p 6379 LRANGE mylist 0 1 2>&1
    if ($result -contains "item1" -and $result -contains "item2" -and -not ($result -contains "item3")) {
        Write-Host "  ✅ PASS: LRANGE with range [0, 1]" -ForegroundColor Green
        $Global:TestResults.Passed++
    } else {
        Write-Host "  ❌ FAIL: LRANGE [0, 1] should return first 2 items only" -ForegroundColor Red
        Write-Host "     Actual: $($result -join ', ')" -ForegroundColor Yellow
        $Global:TestResults.Failed++
    }
    
    # Test LRANGE with negative indices
    $result = redis-cli -p 6379 LRANGE mylist -2 -1 2>&1
    if ($result -contains "item2" -and $result -contains "item3") {
        Write-Host "  ✅ PASS: LRANGE with negative indices [-2, -1]" -ForegroundColor Green
        $Global:TestResults.Passed++
    } else {
        Write-Host "  ❌ FAIL: LRANGE [-2, -1] should return last 2 items" -ForegroundColor Red
        Write-Host "     Actual: $($result -join ', ')" -ForegroundColor Yellow
        $Global:TestResults.Failed++
    }
    
} finally {
    Stop-RedisServer -Process $server
}

# Summary
$success = Write-TestSummary

if (-not $success) {
    exit 1
}

exit 0
