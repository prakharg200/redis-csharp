# TestHelper.psm1
# Common helper functions for Redis testing

# Test result tracking
$Global:TestResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Tests = @()
}

function Start-RedisServer {
    param(
        [int]$Port = 6379,
        [string[]]$AdditionalArgs = @()
    )
    
    Write-Host "🚀 Starting Redis server on port $Port..." -ForegroundColor Cyan
    
    $processArgs = @("run", "--") + @("--port", $Port) + $AdditionalArgs
    
    $process = Start-Process -FilePath "dotnet" `
        -ArgumentList $processArgs `
        -WorkingDirectory (Get-Location) `
        -PassThru `
        -NoNewWindow `
        -RedirectStandardOutput "redis-output-$Port.log" `
        -RedirectStandardError "redis-error-$Port.log"
    
    # Wait for server to start
    Start-Sleep -Milliseconds 500
    
    # Verify server is running
    $maxRetries = 10
    $retryCount = 0
    $serverReady = $false
    
    while (-not $serverReady -and $retryCount -lt $maxRetries) {
        try {
            $result = redis-cli -p $Port PING 2>&1
            if ($result -match "PONG") {
                $serverReady = $true
                Write-Host "✅ Redis server started successfully on port $Port" -ForegroundColor Green
            }
        } catch {
            $retryCount++
            Start-Sleep -Milliseconds 200
        }
    }
    
    if (-not $serverReady) {
        Write-Host "❌ Failed to start Redis server on port $Port" -ForegroundColor Red
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        return $null
    }
    
    return $process
}

function Stop-RedisServer {
    param(
        [System.Diagnostics.Process]$Process
    )
    
    if ($Process -and -not $Process.HasExited) {
        Write-Host "🛑 Stopping Redis server (PID: $($Process.Id))..." -ForegroundColor Yellow
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 200
    }
    
    # Clean up log files
    Remove-Item "redis-output-*.log" -ErrorAction SilentlyContinue
    Remove-Item "redis-error-*.log" -ErrorAction SilentlyContinue
}

function Test-RedisCommand {
    param(
        [string]$Command,
        [string]$ExpectedOutput,
        [int]$Port = 6379,
        [string]$TestName = "Redis Command Test",
        [switch]$Regex,
        [switch]$Contains
    )
    
    try {
        $result = Invoke-Expression "redis-cli -p $Port $Command" 2>&1 | Out-String
        $result = $result.Trim()
        
        $passed = $false
        
        if ($Regex) {
            $passed = $result -match $ExpectedOutput
        } elseif ($Contains) {
            $passed = $result -like "*$ExpectedOutput*"
        } else {
            $passed = $result -eq $ExpectedOutput
        }
        
        if ($passed) {
            Write-Host "  ✅ PASS: $TestName" -ForegroundColor Green
            $Global:TestResults.Passed++
            $Global:TestResults.Tests += @{
                Name = $TestName
                Status = "PASS"
                Command = $Command
                Expected = $ExpectedOutput
                Actual = $result
            }
            return $true
        } else {
            Write-Host "  ❌ FAIL: $TestName" -ForegroundColor Red
            Write-Host "     Expected: $ExpectedOutput" -ForegroundColor Yellow
            Write-Host "     Actual:   $result" -ForegroundColor Yellow
            $Global:TestResults.Failed++
            $Global:TestResults.Tests += @{
                Name = $TestName
                Status = "FAIL"
                Command = $Command
                Expected = $ExpectedOutput
                Actual = $result
            }
            return $false
        }
    } catch {
        Write-Host "  ❌ ERROR: $TestName" -ForegroundColor Red
        Write-Host "     Error: $_" -ForegroundColor Red
        $Global:TestResults.Failed++
        $Global:TestResults.Tests += @{
            Name = $TestName
            Status = "ERROR"
            Command = $Command
            Error = $_.Exception.Message
        }
        return $false
    }
}

function Assert-Equal {
    param(
        [string]$Actual,
        [string]$Expected,
        [string]$TestName
    )
    
    if ($Actual -eq $Expected) {
        Write-Host "  ✅ PASS: $TestName" -ForegroundColor Green
        $Global:TestResults.Passed++
        return $true
    } else {
        Write-Host "  ❌ FAIL: $TestName" -ForegroundColor Red
        Write-Host "     Expected: $Expected" -ForegroundColor Yellow
        Write-Host "     Actual:   $Actual" -ForegroundColor Yellow
        $Global:TestResults.Failed++
        return $false
    }
}

function Get-TestResults {
    return $Global:TestResults
}

function Reset-TestResults {
    $Global:TestResults = @{
        Passed = 0
        Failed = 0
        Skipped = 0
        Tests = @()
    }
}

function Write-TestSummary {
    $results = Get-TestResults
    $total = $results.Passed + $results.Failed + $results.Skipped
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "                   TEST SUMMARY                     " -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Total Tests:  $total" -ForegroundColor White
    Write-Host "✅ Passed:    $($results.Passed)" -ForegroundColor Green
    Write-Host "❌ Failed:    $($results.Failed)" -ForegroundColor Red
    Write-Host "⏭️  Skipped:   $($results.Skipped)" -ForegroundColor Yellow
    
    $successRate = if ($total -gt 0) { [math]::Round(($results.Passed / $total) * 100, 2) } else { 0 }
    Write-Host "Success Rate: $successRate%" -ForegroundColor $(if ($successRate -eq 100) { "Green" } elseif ($successRate -ge 70) { "Yellow" } else { "Red" })
    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    return $results.Failed -eq 0
}

function Read-CompletedTasks {
    param(
        [string]$PlanFile = "IMPLEMENTATION-PLAN.md"
    )
    
    if (-not (Test-Path $PlanFile)) {
        Write-Warning "Implementation plan file not found: $PlanFile"
        return @()
    }
    
    $content = Get-Content $PlanFile -Raw
    $completedTasks = @()
    
    # Look for tasks marked with ✅
    if ($content -match '(?s)### (\d+\.\d+).*?(?=###|\z)') {
        $taskSections = [regex]::Matches($content, '(?s)### (\d+\.\d+)[^\n]*\n(.*?)(?=###|\z)')
        
        foreach ($match in $taskSections) {
            $taskNumber = $match.Groups[1].Value
            $taskContent = $match.Groups[2].Value
            
            # Check if task is marked complete (has ✅ emoji or checkbox [✅])
            if ($taskContent -match '✅|completed') {
                $completedTasks += $taskNumber
            }
        }
    }
    
    Write-Host "📋 Found $($completedTasks.Count) completed tasks" -ForegroundColor Cyan
    
    return $completedTasks
}

function Test-RedisCliAvailable {
    # First, try to find redis-cli in PATH
    try {
        $result = redis-cli --version 2>&1
        if ($result -match "redis-cli") {
            return $true
        }
    } catch {
        # If not in PATH, try common installation locations
        $commonPaths = @(
            "C:\Users\$env:USERNAME\redis\redis-cli.exe",
            "C:\redis\redis-cli.exe",
            "C:\Program Files\Redis\redis-cli.exe",
            "$env:LOCALAPPDATA\Redis\redis-cli.exe"
        )
        
        foreach ($path in $commonPaths) {
            if (Test-Path $path) {
                try {
                    $result = & $path --version 2>&1
                    if ($result -match "redis-cli") {
                        # Set an alias for this session
                        Set-Alias -Name redis-cli -Value $path -Scope Global
                        return $true
                    }
                } catch {
                    continue
                }
            }
        }
    }
    return $false
}

function Get-RedisCliPath {
    # First, try to find redis-cli in PATH
    try {
        $result = redis-cli --version 2>&1
        if ($result -match "redis-cli") {
            return "redis-cli"
        }
    } catch {
        # If not in PATH, try common installation locations
        $commonPaths = @(
            "C:\Users\$env:USERNAME\redis\redis-cli.exe",
            "C:\redis\redis-cli.exe",
            "C:\Program Files\Redis\redis-cli.exe",
            "$env:LOCALAPPDATA\Redis\redis-cli.exe"
        )
        
        foreach ($path in $commonPaths) {
            if (Test-Path $path) {
                try {
                    $result = & $path --version 2>&1
                    if ($result -match "redis-cli") {
                        # Set an alias for this session
                        Set-Alias -Name redis-cli -Value $path -Scope Global
                        return $path
                    }
                } catch {
                    continue
                }
            }
        }
    }
    return $null
}

# Export functions
Export-ModuleMember -Function @(
    'Start-RedisServer',
    'Stop-RedisServer',
    'Test-RedisCommand',
    'Assert-Equal',
    'Get-TestResults',
    'Reset-TestResults',
    'Write-TestSummary',
    'Read-CompletedTasks',
    'Test-RedisCliAvailable',
    'Get-RedisCliPath'
)
