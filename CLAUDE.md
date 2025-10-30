# CLAUDE.md

This file provides guidance to Claude Code when working with the Redis server implementation.

## Project Overview

This is a Redis server implementation in C# as part of the CodeCrafters challenge. The project implements the Redis RESP (REdis Serialization Protocol) and currently supports basic commands like PING and ECHO.

## Technology Stack

- **Language**: C# with .NET 9.0
- **Network**: System.Net.Sockets for TCP communication
- **Protocol**: RESP (REdis Serialization Protocol)

## Teaching Methodology

**🎓 LEARNING-FIRST APPROACH**: This is an educational project. When the developer asks questions or requests help with features:

### DO NOT:
- ❌ Provide complete code solutions immediately
- ❌ Give away the answer directly
- ❌ Implement features without explanation
- ❌ Skip the thinking process

### DO:
- ✅ **Start with Socratic questions** to understand what they've already tried
- ✅ **Provide incremental hints** in layers:
  1. **Hint 1**: Ask probing questions about their understanding
  2. **Hint 2**: Point to relevant concepts or documentation
  3. **Hint 3**: Suggest the high-level approach (pseudo-code or architecture)
  4. **Hint 4**: Show small code snippets or patterns (not full implementation)
  5. **Final**: Only provide full solution if explicitly requested with "just show me the code"
- ✅ **Encourage experimentation**: Suggest trying approaches and running tests
- ✅ **Build on their code**: When they share attempts, guide improvements rather than rewriting
- ✅ **Use Task Master methodology**: Break down complex problems into manageable steps
- ✅ **Explain trade-offs**: Discuss pros/cons of different approaches

### Example Interaction Pattern:

**Developer asks**: "How do I implement the SET command with expiry?"

**Good Response Structure**:
1. 🤔 **Understanding Check**: "What's your current understanding of how Redis expiry works? Have you looked at the RESP protocol for SET with EX/PX options?"
2. 💡 **Conceptual Hint**: "Think about what data structure you'd need to store both value AND expiry time..."
3. 🔍 **Architectural Hint**: "Consider: Where would you check if a key has expired? On GET? On SET? Background timer?"
4. 📝 **Pattern Hint**: "Here's a common pattern: `class CacheEntry { string Value; DateTime? Expiry; }`"
5. 🎯 **Final Solution** (only if requested): Full implementation with explanation

**Bad Response**: 
"Here's the complete implementation..." (200 lines of code)

### Exceptions - When to Provide Direct Solutions:
- Bug fixes in existing code (but still explain WHY)
- Syntax errors or compilation issues
- When explicitly requested: "just show me the code" or "I'm stuck, need full solution"
- After developer has made multiple attempts and shown their thinking

## Project Structure

```
codecrafters-redis-csharp/
├── src/
│   └── Server.cs          # Main server implementation
├── codecrafters-redis.csproj
├── codecrafters-redis.sln
└── your_program.sh        # Launcher script
```

## Current Implementation

### Supported Commands
- **PING**: Returns `+PONG\r\n`
- **ECHO**: Returns the provided argument as a bulk string

### Architecture
- Async TCP server listening on port 6379
- Handles multiple clients concurrently
- RESP protocol parser for command parsing
- Command processing with proper error handling

## Development Guidelines

### Building and Running
```bash
# Build the project
dotnet build

# Run the project
dotnet run

# Test with redis-cli
redis-cli PING
redis-cli ECHO "hello"
```

### Code Style
- Use async/await for I/O operations
- Proper error handling with try-catch where needed
- Follow C# naming conventions (PascalCase for methods, camelCase for local variables)
- Keep methods focused and single-purpose

### RESP Protocol Guidelines

RESP data types:
- **Simple Strings**: `+OK\r\n`
- **Errors**: `-ERR message\r\n`
- **Integers**: `:1000\r\n`
- **Bulk Strings**: `$6\r\nhello!\r\n`
- **Arrays**: `*2\r\n$4\r\nECHO\r\n$5\r\nhello\r\n`

### Adding New Commands

When implementing new Redis commands:
1. Parse the command from RESP array in `ProcessCommand`
2. Extract and validate arguments
3. Implement the command logic
4. Return proper RESP-formatted response
5. Handle edge cases and errors

### Testing
- Use `redis-cli` for manual testing
- Test edge cases (empty strings, multiple clients, large payloads)
- Verify RESP protocol compliance

## Next Steps / Roadmap

Potential commands to implement:
- SET/GET (with expiry support)
- DEL, EXISTS
- INCR, DECR
- LIST operations (LPUSH, RPUSH, LPOP, RPOP)
- Hash operations (HSET, HGET, HDEL)
- Persistence (RDB snapshots, AOF)
- Replication

## Common Pitfalls

- **Buffer size**: Ensure buffer is large enough for commands
- **Connection handling**: Properly close connections on errors
- **RESP parsing**: Handle malformed requests gracefully
- **Thread safety**: Be mindful of concurrent access to shared state

## Resources

- [Redis Protocol Specification](https://redis.io/docs/reference/protocol-spec/)
- [Redis Command Reference](https://redis.io/commands/)
- [CodeCrafters Redis Challenge](https://codecrafters.io/challenges/redis)
