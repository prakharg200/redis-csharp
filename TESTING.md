# Redis Testing Framework 🧪

This document describes the automated testing framework for the Redis implementation.

## 📋 Overview

The testing framework consists of:
- **Local PowerShell Test Runner** - For rapid local development and testing
- **GitHub Actions CI/CD** - For automated testing on push/PR
- **Smart Task Detection** - Automatically runs tests based on completed tasks in `IMPLEMENTATION-PLAN.md`
- **Structured Test Suites** - Organized by stages and tasks

## 🚀 Quick Start

### Running Tests Locally

```powershell
# Run all tests for completed tasks
.\run-tests.ps1

# Run tests for current implemented features
.\run-tests.ps1 -Current

# Run tests for specific stage
.\run-tests.ps1 -Stage 1

# Run specific task test
.\run-tests.ps1 -Stage 1 -Task 1

# Run with verbose output
.\run-tests.ps1 -Verbose

# Continue running tests even if some fail
.\run-tests.ps1 -ContinueOnFailure

# Skip build step (if already built)
.\run-tests.ps1 -SkipBuild
```

## 📁 Test Structure

```
tests/
├── TestHelper.psm1                          # Common test utilities
├── Stage1_Replication/
│   ├── Test_1_1_ConfigurePort.ps1          # Task 1.1: Port configuration
│   ├── Test_1_2_InfoCommand.ps1            # Task 1.2: INFO command
│   └── Test_Current_Features.ps1           # Tests for all current features
├── Stage2_RDB/
├── Stage3_PubSub/
├── Stage4_SortedSets/
├── Stage5_Geospatial/
├── Stage6_Lists/
├── Stage7_Streams/
└── Stage8_Transactions/
```

## 🧩 Test Helper Functions

The `TestHelper.psm1` module provides common utilities:

### Server Management
```powershell
# Start Redis server on specific port
$server = Start-RedisServer -Port 6379

# Stop Redis server
Stop-RedisServer -Process $server
```

### Test Commands
```powershell
# Test a Redis command with expected output
Test-RedisCommand -Command "PING" -ExpectedOutput "PONG" -Port 6379 -TestName "PING Test"

# Test with regex matching
Test-RedisCommand -Command "INFO" -ExpectedOutput "role:master" -Regex -TestName "INFO Test"

# Test with contains matching
Test-RedisCommand -Command "INFO replication" -ExpectedOutput "master" -Contains -TestName "INFO Contains"
```

### Assertions
```powershell
# Assert equality
Assert-Equal -Actual $result -Expected "PONG" -TestName "PING Response"
```

### Result Management
```powershell
# Reset test results
Reset-TestResults

# Get current test results
$results = Get-TestResults

# Write test summary
Write-TestSummary
```

### Task Detection
```powershell
# Read completed tasks from IMPLEMENTATION-PLAN.md
$completedTasks = Read-CompletedTasks
```

## ✅ Marking Tasks as Complete

To enable automatic testing for a task, mark it as complete in `IMPLEMENTATION-PLAN.md`:

**Option 1: Add ✅ emoji**
```markdown
### 1.1 Configure Listening Port ✅
```

**Option 2: Add "completed" keyword**
```markdown
### 1.1 Configure Listening Port

Status: completed
```

The test runner will automatically detect completed tasks and run corresponding tests.

## 🎯 Writing New Tests

### Test File Template

```powershell
# Test X.Y: Task Name
# Description of what this test validates

param(
    [switch]$Verbose
)

Import-Module "$PSScriptRoot\..\TestHelper.psm1" -Force

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Test X.Y: Task Name                               ║" -ForegroundColor Cyan
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
    # Test 1: Description
    Write-Host "Test 1: Description..." -ForegroundColor Yellow
    Test-RedisCommand -Command "YOUR_COMMAND" -ExpectedOutput "EXPECTED" -TestName "Test Description"
    
    # Test 2: Another test
    Write-Host ""
    Write-Host "Test 2: Another test..." -ForegroundColor Yellow
    Test-RedisCommand -Command "ANOTHER_COMMAND" -ExpectedOutput "EXPECTED" -TestName "Another Test"
    
} finally {
    Stop-RedisServer -Process $server
}

# Summary
$success = Write-TestSummary

if (-not $success) {
    exit 1
}

exit 0
```

### Test Naming Convention

Test files should follow this naming pattern:
```
Test_<Stage>_<Task>_<Description>.ps1
```

Examples:
- `Test_1_1_ConfigurePort.ps1` - Stage 1, Task 1
- `Test_1_2_InfoCommand.ps1` - Stage 1, Task 2
- `Test_2_1_RDBConfig.ps1` - Stage 2, Task 1

## 🔄 GitHub Actions CI/CD

Tests run automatically on:
- Push to `main`, `master`, or `develop` branches
- Pull requests to these branches
- Manual workflow dispatch

### Workflow Features
- ✅ Runs on Windows and Linux
- ✅ Installs Redis CLI automatically
- ✅ Builds project before testing
- ✅ Reports test results
- ✅ Continues on non-critical failures

### Viewing Results

1. Go to your repository on GitHub
2. Click the "Actions" tab
3. Select a workflow run to see details
4. Check logs for test output

## 📊 Test Output

### Successful Test
```
✅ PASS: PING returns PONG
```

### Failed Test
```
❌ FAIL: PING returns PONG
   Expected: PONG
   Actual:   PANG
```

### Test Summary
```
═══════════════════════════════════════════════════
                   TEST SUMMARY
═══════════════════════════════════════════════════
Total Tests:  10
✅ Passed:    9
❌ Failed:    1
⏭️  Skipped:   0
Success Rate: 90%
═══════════════════════════════════════════════════
```

## 🐛 Troubleshooting

### redis-cli not found

**Windows:**
```powershell
# Install via Chocolatey
choco install redis-64 -y

# Or download from https://github.com/microsoftarchive/redis/releases
```

**Linux/macOS:**
```bash
# Ubuntu/Debian
sudo apt-get install redis-tools

# macOS
brew install redis
```

### Server fails to start

1. Check if port is already in use:
   ```powershell
   netstat -ano | findstr :6379
   ```

2. Kill existing process:
   ```powershell
   Stop-Process -Id <PID> -Force
   ```

3. Try a different port:
   ```powershell
   .\run-tests.ps1 -Stage 1 -Task 1
   ```

### Build fails

```powershell
# Clean and rebuild
dotnet clean
dotnet build --configuration Release
```

### Tests hang or timeout

- Increase timeout in `Start-RedisServer` function
- Check server logs: `redis-output-*.log` and `redis-error-*.log`
- Verify server is responding: `redis-cli -p 6379 PING`

## 📝 Best Practices

1. **Test One Thing**: Each test should verify one specific behavior
2. **Clear Names**: Use descriptive test names that explain what's being tested
3. **Clean Up**: Always stop servers in `finally` blocks
4. **Assertions**: Use helper functions for consistent output
5. **Documentation**: Comment complex test logic
6. **Idempotent**: Tests should be runnable multiple times with same results

## 🔮 Future Enhancements

- [ ] Add test coverage reporting
- [ ] Create performance benchmarks
- [ ] Add stress tests (many concurrent clients)
- [ ] Implement test parallelization
- [ ] Add mutation testing
- [ ] Create visual test reports (HTML)
- [ ] Add docker-compose for complex scenarios
- [ ] Implement property-based testing

## 🆘 Getting Help

If tests fail or you need assistance:

1. Check test output for specific error messages
2. Review logs: `redis-output-*.log`, `redis-error-*.log`
3. Run with `-Verbose` flag for detailed output
4. Verify your implementation against `IMPLEMENTATION-PLAN.md`
5. Ask Claude for hints (following the learning-first approach!)

## 📚 Resources

- [Redis Protocol Specification](https://redis.io/docs/reference/protocol-spec/)
- [Redis Commands Reference](https://redis.io/commands/)
- [PowerShell Testing Best Practices](https://pester.dev/docs/quick-start)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

---

Happy Testing! 🎉
