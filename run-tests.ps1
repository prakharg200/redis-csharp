# Redis Implementation Test Runner
# Runs tests for implemented features based on IMPLEMENTATION-PLAN.md

param(
    [int]$Stage = 0,           # Run specific stage (0 = all)
    [int]$Task = 0,            # Run specific task (0 = all tasks in stage)
    [switch]$Current,          # Run tests for currently implemented features
    [switch]$Verbose,          # Verbose output
    [switch]$SkipBuild,        # Skip build step
    [switch]$ContinueOnFailure # Continue running tests even if some fail
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║                                                      ║" -ForegroundColor Magenta
Write-Host "║        Redis Implementation Test Runner 🧪          ║" -ForegroundColor Magenta
Write-Host "║                                                      ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

# Check prerequisites
Write-Host "🔍 Checking prerequisites..." -ForegroundColor Cyan

# Check if redis-cli is available
$redisCliPath = $null

# Try to find redis-cli using Get-Command
$redisCmd = Get-Command redis-cli -ErrorAction SilentlyContinue
if ($redisCmd) {
    $redisCliPath = $redisCmd.Source
    $version = & $redisCliPath --version
    Write-Host "✅ redis-cli found in PATH: $version" -ForegroundColor Green
} else {
    # If not in PATH, try common installation locations
    $username = [Environment]::UserName
    $commonPaths = @(
        "C:\Users\$username\redis\redis-cli.exe",
        "$env:USERPROFILE\redis\redis-cli.exe",
        "C:\redis\redis-cli.exe",
        "C:\Program Files\Redis\redis-cli.exe",
        "$env:LOCALAPPDATA\Redis\redis-cli.exe"
    )
    
    Write-Host "   redis-cli not in PATH, checking common locations..." -ForegroundColor Yellow
    
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            try {
                $version = & $path --version
                $redisCliPath = $path
                Write-Host "✅ redis-cli found at: $path" -ForegroundColor Green
                Write-Host "   Version: $version" -ForegroundColor Green
                
                # Add directory to PATH for this session
                $redisDir = Split-Path $path -Parent
                if ($env:PATH -notlike "*$redisDir*") {
                    $env:PATH += ";$redisDir"
                }
                
                # Set an alias for this session
                Set-Alias -Name redis-cli -Value $path -Scope Global
                break
            } catch {
                continue
            }
        }
    }
}

if (-not $redisCliPath) {
    Write-Host "❌ redis-cli not found. Please install Redis CLI." -ForegroundColor Red
    Write-Host "   Download from: https://redis.io/download" -ForegroundColor Yellow
    Write-Host "   Or run: .\setup-redis-path.ps1 to add it to PATH" -ForegroundColor Yellow
    exit 1
}

# Check if .NET is available
try {
    $dotnetVersion = dotnet --version 2>&1
    Write-Host "✅ .NET found: $dotnetVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ .NET not found. Please install .NET SDK." -ForegroundColor Red
    exit 1
}

# Build the project
if (-not $SkipBuild) {
    Write-Host ""
    Write-Host "🔨 Building project..." -ForegroundColor Cyan
    $buildOutput = dotnet build --configuration Release 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Build failed!" -ForegroundColor Red
        Write-Host $buildOutput
        exit 1
    }
    Write-Host "✅ Build successful!" -ForegroundColor Green
}

# Import test helper
Import-Module "$PSScriptRoot\tests\TestHelper.psm1" -Force

# Determine which tests to run
$testsToRun = @()

if ($Current) {
    Write-Host ""
    Write-Host "📝 Running tests for currently implemented features..." -ForegroundColor Cyan
    $testsToRun += @{
        Name = "Current Features"
        Path = "tests\Stage1_Replication\Test_Current_Features.ps1"
    }
} elseif ($Stage -gt 0) {
    Write-Host ""
    Write-Host "📝 Running tests for Stage $Stage..." -ForegroundColor Cyan
    
    # Map stage numbers to directories
    $stageMap = @{
        1 = "Stage1_Replication"
        2 = "Stage2_RDB"
        3 = "Stage3_PubSub"
        4 = "Stage4_SortedSets"
        5 = "Stage5_Geospatial"
        6 = "Stage6_Lists"
        7 = "Stage7_Streams"
        8 = "Stage8_Transactions"
    }
    
    $stageDir = $stageMap[$Stage]
    if (-not $stageDir) {
        Write-Host "❌ Invalid stage number: $Stage" -ForegroundColor Red
        exit 1
    }
    
    $stagePath = Join-Path $PSScriptRoot "tests\$stageDir"
    
    if (Test-Path $stagePath) {
        if ($Task -gt 0) {
            # Run specific task
            $taskFile = Get-ChildItem -Path $stagePath -Filter "Test_${Stage}_${Task}_*.ps1" | Select-Object -First 1
            if ($taskFile) {
                $testsToRun += @{
                    Name = "Stage $Stage - Task $Task"
                    Path = $taskFile.FullName
                }
            } else {
                Write-Host "⚠️  No test found for Stage $Stage, Task $Task" -ForegroundColor Yellow
            }
        } else {
            # Run all tasks in stage
            $testFiles = Get-ChildItem -Path $stagePath -Filter "Test_*.ps1"
            foreach ($file in $testFiles) {
                $testsToRun += @{
                    Name = $file.BaseName
                    Path = $file.FullName
                }
            }
        }
    } else {
        Write-Host "⚠️  No tests found for Stage $Stage" -ForegroundColor Yellow
    }
} else {
    # Read completed tasks from implementation plan
    Write-Host ""
    Write-Host "📖 Reading IMPLEMENTATION-PLAN.md to detect completed tasks..." -ForegroundColor Cyan
    
    $completedTasks = Read-CompletedTasks -PlanFile "IMPLEMENTATION-PLAN.md"
    
    if ($completedTasks.Count -eq 0) {
        Write-Host "ℹ️  No tasks marked as completed in IMPLEMENTATION-PLAN.md" -ForegroundColor Yellow
        Write-Host "   Running tests for currently implemented features instead..." -ForegroundColor Yellow
        $testsToRun += @{
            Name = "Current Features"
            Path = "tests\Stage1_Replication\Test_Current_Features.ps1"
        }
    } else {
        # For now, run current features test
        # TODO: Map completed tasks to specific test files
        Write-Host "ℹ️  Found completed tasks: $($completedTasks -join ', ')" -ForegroundColor Cyan
        Write-Host "   Running comprehensive test suite..." -ForegroundColor Cyan
        
        $testsToRun += @{
            Name = "Current Features"
            Path = "tests\Stage1_Replication\Test_Current_Features.ps1"
        }
        
        # Add Stage 1.1 test if it's marked complete
        if ($completedTasks -contains "1.1") {
            $testsToRun += @{
                Name = "Stage 1.1 - Configure Port"
                Path = "tests\Stage1_Replication\Test_1_1_ConfigurePort.ps1"
            }
        }
    }
}

if ($testsToRun.Count -eq 0) {
    Write-Host "⚠️  No tests to run!" -ForegroundColor Yellow
    exit 0
}

# Run tests
Write-Host ""
Write-Host "🧪 Running $($testsToRun.Count) test suite(s)..." -ForegroundColor Cyan
Write-Host ""

$overallResults = @{
    TotalSuites = $testsToRun.Count
    PassedSuites = 0
    FailedSuites = 0
    TotalTests = 0
    PassedTests = 0
    FailedTests = 0
}

foreach ($test in $testsToRun) {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "Running: $($test.Name)" -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    
    if (-not (Test-Path $test.Path)) {
        Write-Host "⚠️  Test file not found: $($test.Path)" -ForegroundColor Yellow
        $overallResults.FailedSuites++
        continue
    }
    
    try {
        $result = & $test.Path
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            $overallResults.PassedSuites++
            Write-Host "✅ Test suite passed: $($test.Name)" -ForegroundColor Green
        } else {
            $overallResults.FailedSuites++
            Write-Host "❌ Test suite failed: $($test.Name)" -ForegroundColor Red
            
            if (-not $ContinueOnFailure) {
                Write-Host ""
                Write-Host "❌ Stopping test execution due to failure. Use -ContinueOnFailure to continue." -ForegroundColor Red
                break
            }
        }
    } catch {
        $overallResults.FailedSuites++
        Write-Host "❌ Error running test suite: $($test.Name)" -ForegroundColor Red
        Write-Host "   Error: $_" -ForegroundColor Red
        
        if (-not $ContinueOnFailure) {
            Write-Host ""
            Write-Host "❌ Stopping test execution due to error. Use -ContinueOnFailure to continue." -ForegroundColor Red
            break
        }
    }
    
    Write-Host ""
}

# Overall summary
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║              OVERALL TEST SUMMARY                    ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""
Write-Host "Test Suites Run:    $($overallResults.TotalSuites)" -ForegroundColor White
Write-Host "✅ Suites Passed:  $($overallResults.PassedSuites)" -ForegroundColor Green
Write-Host "❌ Suites Failed:  $($overallResults.FailedSuites)" -ForegroundColor Red
Write-Host ""

$successRate = if ($overallResults.TotalSuites -gt 0) { 
    [math]::Round(($overallResults.PassedSuites / $overallResults.TotalSuites) * 100, 2) 
} else { 
    0 
}

Write-Host "Overall Success Rate: $successRate%" -ForegroundColor $(
    if ($successRate -eq 100) { "Green" } 
    elseif ($successRate -ge 70) { "Yellow" } 
    else { "Red" }
)
Write-Host ""

if ($overallResults.FailedSuites -gt 0) {
    Write-Host "❌ Some tests failed. Please review the output above." -ForegroundColor Red
    exit 1
} else {
    Write-Host "✅ All tests passed! Great work! 🎉" -ForegroundColor Green
    exit 0
}
