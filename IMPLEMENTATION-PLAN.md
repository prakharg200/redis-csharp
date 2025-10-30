# Redis Implementation Plan

This document provides a comprehensive, stage-by-stage plan for implementing Redis features. Each stage builds upon previous knowledge and follows a hint-based learning approach.

---

## 📋 Current Status

### ✅ Completed Features
- Basic TCP server on port 6379
- RESP protocol parsing (arrays and bulk strings)
- Commands: PING, ECHO
- Commands: SET, GET (with PX expiry)
- Commands: RPUSH, LRANGE (basic list operations)
- In-memory data storage with concurrent dictionary
- Expiry checking on GET

### 🚧 Next Immediate Task
- **Configure listening port**: Allow server to start on custom port via command-line argument

---

## Stage 1: Replication

Replication allows Redis instances to be exact copies of master instances. Replicas automatically reconnect to masters every time the link breaks.

### 1.1 Configure Listening Port ⬅️ **YOU ARE HERE**

**Goal**: Start Redis server on a custom port specified via command-line arguments.

**Learning Objectives**:
- Understand command-line argument parsing in C#
- Learn about port configuration and validation
- Handle default vs custom configuration

**Tasks**:
1. Read command-line arguments (look for `--port` flag)
2. Parse and validate port number (1-65535)
3. Replace hardcoded `6379` with parsed port value
4. Test: `dotnet run -- --port 6380` should start server on 6380
5. Test: `redis-cli -p 6380 PING` should return PONG

**Hints to Consider**:
- Top-level statements have access to `args` variable
- Port validation: Must be between 1 and 65535
- Default to 6379 if no argument provided

---

### 1.2 The INFO Command

**Goal**: Implement `INFO` command to return server information.

**Learning Objectives**:
- Understand Redis INFO command structure
- Learn about server metadata and statistics
- Practice formatting multi-line RESP responses

**Tasks**:
1. Create an `INFO` command handler
2. Return basic server information (initially just role=master)
3. Format response as RESP bulk string
4. Support optional sections (e.g., `INFO replication`)
5. Test: `redis-cli INFO` and `redis-cli INFO replication`

**Key Information to Include**:
```
# Replication
role:master
master_replid:<40-char-alphanumeric-string>
master_repl_offset:0
```

**Hints to Consider**:
- INFO returns bulk string, not simple string
- Each line ends with `\r\n`
- Generate a random 40-character replication ID once at startup

---

### 1.3 The INFO Command on a Replica

**Goal**: Modify INFO command to return different information when server runs as replica.

**Learning Objectives**:
- Understand master vs replica roles
- Learn about `--replicaof` configuration
- Practice conditional response formatting

**Tasks**:
1. Parse `--replicaof <MASTER_HOST> <MASTER_PORT>` argument
2. Store master connection information
3. Modify INFO to return `role:slave` when running as replica
4. Test: `dotnet run -- --port 6380 --replicaof localhost 6379`

**Key Information to Include**:
```
# Replication
role:slave
master_host:<host>
master_port:<port>
```

**Hints to Consider**:
- Need to store whether this instance is master or replica
- Master host/port stored at startup
- Don't connect to master yet—just store the configuration

---

### 1.4 Initial Replication ID and Offset

**Goal**: Generate and track replication ID and offset.

**Learning Objectives**:
- Understand replication identifiers
- Learn about replication offset tracking
- Practice generating pseudo-random strings

**Tasks**:
1. Generate a 40-character alphanumeric replication ID at startup
2. Initialize master_repl_offset to 0
3. Include these in INFO replication response
4. Store as server state (instance variables or global state)

**Hints to Consider**:
- Replication ID: 40 chars, alphanumeric (0-9, a-z)
- Can use `Random` or `Guid.NewGuid()` with transformation
- Offset starts at 0 and increments with each write command
- Masters and replicas both track their own offset

---

### 1.5 Send Handshake (1/3) - PING

**Goal**: Replica sends PING to master during initial handshake.

**Learning Objectives**:
- Understand TCP client connections
- Learn the replication handshake protocol
- Practice async socket communication

**Tasks**:
1. When started as replica, connect to master (TcpClient)
2. Send PING command in RESP format: `*1\r\n$4\r\nPING\r\n`
3. Wait for and validate master's response (+PONG)
4. Keep connection open for next handshake step

**Hints to Consider**:
- Create connection during server startup (if replica)
- Use TcpClient for outgoing connections
- Store master connection as persistent socket/stream
- Handle connection failures gracefully

---

### 1.6 Send Handshake (2/3) - REPLCONF listening-port

**Goal**: Replica sends its listening port to master.

**Learning Objectives**:
- Understand REPLCONF protocol
- Learn about replica registration with master
- Practice multi-step handshake protocols

**Tasks**:
1. After PING succeeds, send REPLCONF with listening port
2. Format: `*3\r\n$8\r\nREPLCONF\r\n$14\r\nlistening-port\r\n$<len>\r\n<port>\r\n`
3. Wait for +OK response
4. Handle errors if master doesn't acknowledge

**Hints to Consider**:
- REPLCONF is array of 3 elements: command, subcommand, value
- Port is your server's listening port (the one clients connect to)
- Master should store replica information

---

### 1.7 Send Handshake (3/3) - REPLCONF capa psync2

**Goal**: Replica announces PSYNC2 capability to master.

**Learning Objectives**:
- Understand capability negotiation
- Learn about PSYNC versions
- Complete the handshake sequence

**Tasks**:
1. Send: `*3\r\n$8\r\nREPLCONF\r\n$4\r\ncapa\r\n$6\r\npsync2\r\n`
2. Wait for +OK response
3. Prepare for PSYNC command (next stage)

**Hints to Consider**:
- "capa" = capability announcement
- "psync2" = Partial Sync version 2
- This tells master what replication features replica supports

---

### 1.8 Receive Handshake (1/2) - Master Receives PING & REPLCONF

**Goal**: Master accepts and responds to replica handshake.

**Learning Objectives**:
- Implement server-side handshake handling
- Learn about replica tracking
- Practice stateful connection management

**Tasks**:
1. Add REPLCONF command handler in master
2. Handle `REPLCONF listening-port <port>` - store replica info
3. Handle `REPLCONF capa psync2` - acknowledge capability
4. Track connected replicas (list or dictionary)
5. Return +OK for successful REPLCONF commands

**Data to Track per Replica**:
- Socket/connection
- Listening port
- Capabilities
- Current replication offset

**Hints to Consider**:
- Need to identify which client is in handshake mode
- Store replica metadata in concurrent collection
- Each replica connection is stateful

---

### 1.9 Receive Handshake (2/2) - Handle PSYNC

**Goal**: Master responds to PSYNC command with FULLRESYNC.

**Learning Objectives**:
- Understand PSYNC protocol
- Learn about full vs partial sync
- Prepare for RDB transfer

**Tasks**:
1. Add PSYNC command handler
2. Parse: `PSYNC <replication-id> <offset>`
3. For first sync, return: `+FULLRESYNC <master-replid> 0\r\n`
4. Mark replica as "awaiting RDB transfer"

**Hints to Consider**:
- First sync always triggers FULLRESYNC
- Master sends its replication ID and current offset
- Replica should receive "?" as replication-id and -1 as offset for first sync
- Actual RDB transfer happens next

---

### 1.10 Empty RDB Transfer

**Goal**: Master sends empty RDB file to replica.

**Learning Objectives**:
- Understand RDB file format
- Learn about binary data in RESP
- Practice RDB serialization

**Tasks**:
1. Create minimal empty RDB file (hex-encoded binary)
2. Send as RESP bulk string: `$<length>\r\n<binary-data>`
3. Replica receives and validates RDB
4. Replica acknowledges completion

**Empty RDB (hex)**:
```
524544495330303131fa0972656469732d76657205372e322e30fa0a72656469732d62697473c040fa056374696d65c26d08bc65fa08757365642d6d656dc2b0c41000fa08616f662d62617365c000fff06e3bfec0ff5aa2
```

**Hints to Consider**:
- RDB sent immediately after FULLRESYNC response
- Use `Convert.FromHexString()` to convert hex to bytes
- Length prefix is important for RESP protocol
- Replica should "load" the RDB (for now, just acknowledge receipt)

---

### 1.11 Single-Replica Propagation

**Goal**: Master propagates write commands to one connected replica.

**Learning Objectives**:
- Understand command propagation
- Learn about write command detection
- Practice asynchronous broadcasting

**Tasks**:
1. Identify write commands (SET, DEL, etc.)
2. After executing write command, forward to all replicas
3. Send command in RESP format to replica
4. Don't wait for replica acknowledgment yet
5. Test: SET on master should appear on replica

**Hints to Consider**:
- Only propagate write commands (not read commands)
- Forward exact command received from client
- Use async fire-and-forget (don't block client)
- Track propagation offset

---

### 1.12 Multi-Replica Propagation

**Goal**: Master propagates commands to multiple replicas simultaneously.

**Learning Objectives**:
- Handle multiple replica connections
- Practice concurrent message broadcasting
- Learn about replica failure handling

**Tasks**:
1. Iterate through all connected replicas
2. Send command to each replica concurrently
3. Handle replica disconnections gracefully
4. Remove disconnected replicas from tracking list
5. Test with 2+ replicas connected

**Hints to Consider**:
- Use Task.WhenAll for parallel sends
- Catch exceptions per replica (don't let one failure stop others)
- Consider using channels or queues for replica communication

---

### 1.13 Command Processing (on Replica)

**Goal**: Replica receives and processes commands from master.

**Learning Objectives**:
- Implement replica-side command processing
- Understand read-only vs read-write modes
- Learn about replication offset tracking

**Tasks**:
1. Replica continuously reads commands from master connection
2. Parse and execute write commands (update local data store)
3. Track replication offset (bytes processed)
4. Don't send responses back to master for propagated commands
5. Test: Verify replica has same data as master

**Hints to Consider**:
- Replica has two types of connections: master connection (receive) and client connections (serve reads)
- Need separate read loop for master connection
- Increment offset by bytes received
- Replica should execute commands but not respond to master

---

### 1.14 ACKs with No Commands

**Goal**: Replica sends REPLCONF ACK with current offset.

**Learning Objectives**:
- Understand replication acknowledgments
- Learn about offset synchronization
- Practice periodic status updates

**Tasks**:
1. Master sends: `REPLCONF GETACK *`
2. Replica responds with: `*3\r\n$8\r\nREPLCONF\r\n$3\r\nACK\r\n$<len>\r\n<offset>\r\n`
3. Track bytes processed by replica
4. Test: Send GETACK, verify ACK response

**Hints to Consider**:
- GETACK is a special command that expects response
- Offset = total bytes processed from master
- Include GETACK command itself in offset calculation

---

### 1.15 ACKs with Commands

**Goal**: Track offset accurately when commands are propagated.

**Learning Objectives**:
- Understand offset calculation
- Learn about byte counting in replication
- Practice accurate state tracking

**Tasks**:
1. Increment replica offset for each command received
2. Increment by total bytes: command + RESP overhead
3. Respond to GETACK with accurate offset
4. Test: Propagate commands, then GETACK - verify offset

**Hints to Consider**:
- Count all bytes: `*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$5\r\nvalue\r\n`
- Use `Encoding.UTF8.GetByteCount()` for accuracy
- Offset should match bytes sent by master

---

### 1.16 WAIT with No Replicas

**Goal**: Implement WAIT command when no replicas connected.

**Learning Objectives**:
- Understand WAIT semantics
- Learn about blocking commands
- Handle edge case: no replicas

**Tasks**:
1. Parse: `WAIT <numreplicas> <timeout>`
2. If no replicas connected, return immediately
3. Response: `:0\r\n` (zero replicas acknowledged)
4. Test: `WAIT 1 1000` on master with no replicas

**Hints to Consider**:
- WAIT waits for replicas to acknowledge write commands
- If numreplicas is 0, return immediately
- Timeout in milliseconds

---

### 1.17 WAIT with No Commands

**Goal**: WAIT returns immediately if no writes pending.

**Learning Objectives**:
- Understand write tracking
- Learn about instant WAIT satisfaction
- Practice state checking

**Tasks**:
1. Track whether write commands were issued since last WAIT
2. If no pending writes, return number of connected replicas immediately
3. Response: `:<num-replicas>\r\n`
4. Test: `WAIT 1 1000` without preceding SET

**Hints to Consider**:
- If nothing to replicate, all replicas are "caught up"
- Return min(requested_replicas, connected_replicas)
- No need to send GETACK

---

### 1.18 WAIT with Multiple Commands

**Goal**: WAIT blocks until replicas acknowledge writes.

**Learning Objectives**:
- Implement blocking command logic
- Learn about async waiting with timeout
- Practice replica coordination

**Tasks**:
1. After write commands, track expected replication offset
2. Send REPLCONF GETACK to all replicas
3. Wait for ACK responses with correct offset
4. Block up to timeout milliseconds
5. Return count of replicas that acknowledged
6. Test: `SET key val`, then `WAIT 1 1000`

**Hints to Consider**:
- Use Task.WaitAny with timeout
- Track which replicas have acknowledged
- Return early if required replicas acknowledge
- Return count even if timeout expires

---

## Stage 2: RDB Persistence

RDB is Redis's point-in-time snapshot format. It's a compact, single-file representation of the entire dataset.

### 2.1 RDB File Config

**Goal**: Add command-line options for RDB file configuration.

**Learning Objectives**:
- Understand configuration options
- Learn about RDB file location
- Practice file path handling

**Tasks**:
1. Add `--dir <directory>` argument (RDB file directory)
2. Add `--dbfilename <filename>` argument (default: dump.rdb)
3. Store configuration values
4. Implement CONFIG GET dir
5. Implement CONFIG GET dbfilename
6. Test: `redis-cli CONFIG GET dir`

**Hints to Consider**:
- CONFIG GET returns array: [key, value]
- Store dir and filename as server configuration
- Validate directory exists (or create it)

---

### 2.2 Read a Key

**Goal**: Load RDB file and read a single key.

**Learning Objectives**:
- Understand RDB file format
- Learn about binary parsing
- Practice file I/O

**Tasks**:
1. On startup, check if RDB file exists
2. Parse RDB header: "REDIS" + version
3. Parse database selector opcode (0xFE)
4. Parse key-value pair (opcode 0x00 for string)
5. Load key into data store
6. Test: Create RDB with one key, restart, verify key exists

**RDB Format Basics**:
- Magic string: "REDIS0011"
- Metadata section (optional)
- Database selector: 0xFE + db_number
- Key-value pair: type + key + value
- EOF marker: 0xFF

**Hints to Consider**:
- Use BinaryReader for parsing
- Handle string encoding (length-prefixed)
- Start with simplest case: no expiry, no compression

---

### 2.3 Read a String Value

**Goal**: Parse string values from RDB correctly.

**Learning Objectives**:
- Understand string encoding in RDB
- Learn about length encoding
- Practice binary data handling

**Tasks**:
1. Parse length-encoded strings
2. Handle different length encodings (6-bit, 14-bit, 32-bit)
3. Read string data
4. Store in data store
5. Test: RDB with string value

**Length Encoding**:
- 00xxxxxx: 6-bit length (0-63)
- 01xxxxxx xxxxxxxx: 14-bit length
- 10xxxxxx: special format
- 11xxxxxx: 32-bit length

**Hints to Consider**:
- First 2 bits determine encoding type
- Read variable number of bytes based on encoding
- Then read `length` bytes for actual string

---

### 2.4 Read Multiple Keys

**Goal**: Load RDB with multiple key-value pairs.

**Learning Objectives**:
- Understand iteration in RDB parsing
- Learn about opcode handling
- Practice loop parsing

**Tasks**:
1. Loop through key-value pairs until EOF (0xFF)
2. Handle multiple entries
3. Load all into data store
4. Test: RDB with 3+ keys

**Hints to Consider**:
- Read opcode byte to determine what comes next
- 0x00 = string value
- 0xFE = database selector
- 0xFF = end of file
- Continue until EOF marker

---

### 2.5 Read Multiple String Values

**Goal**: Verify all string types are handled correctly.

**Learning Objectives**:
- Practice robust RDB parsing
- Handle various string lengths
- Ensure no parsing errors

**Tasks**:
1. Test with keys of various lengths
2. Test with values of various lengths
3. Verify all keys loaded correctly
4. Handle edge cases (empty strings)

---

### 2.6 Read Value with Expiry

**Goal**: Load keys with TTL from RDB.

**Learning Objectives**:
- Understand expiry encoding in RDB
- Learn about timestamp storage
- Practice expiry calculation

**Tasks**:
1. Detect expiry opcode: 0xFC (milliseconds) or 0xFD (seconds)
2. Read 8-byte timestamp (milliseconds) or 4-byte (seconds)
3. Read key-value pair following expiry
4. Calculate expiry time from timestamp
5. Store with expiry in data store
6. Test: Keys with past expiry should be excluded

**RDB Expiry Format**:
- 0xFC = expiry in milliseconds (8 bytes, little-endian)
- 0xFD = expiry in seconds (4 bytes, little-endian)
- Followed by type + key + value

**Hints to Consider**:
- Timestamp is Unix epoch time
- Compare with current time
- Skip keys already expired
- Store future expiry in CacheEntry

---

## Stage 3: Pub/Sub

Pub/Sub implements messaging pattern where senders (publishers) send messages to channels, and receivers (subscribers) receive messages from channels they're interested in.

### 3.1 Subscribe to a Channel

**Goal**: Implement SUBSCRIBE command.

**Learning Objectives**:
- Understand pub/sub architecture
- Learn about channel subscriptions
- Practice connection state management

**Tasks**:
1. Implement SUBSCRIBE command: `SUBSCRIBE <channel>`
2. Store subscription: client -> list of channels
3. Mark client connection as "subscribed mode"
4. Return subscription confirmation array
5. Test: `redis-cli SUBSCRIBE news`

**Response Format**:
```
*3
$9
subscribe
$4
news
:1
```
(type, channel, subscription count)

**Hints to Consider**:
- Need to track: channel -> list of subscribers
- Also track: subscriber -> list of channels
- Use concurrent collections for thread-safety

---

### 3.2 Subscribe to Multiple Channels

**Goal**: Handle multiple SUBSCRIBE calls and multiple channels in one call.

**Learning Objectives**:
- Handle variadic commands
- Practice collection management
- Learn about bulk subscriptions

**Tasks**:
1. Support: `SUBSCRIBE channel1 channel2 channel3`
2. Return confirmation for each channel
3. Track total subscription count per client
4. Test: `SUBSCRIBE news sports weather`

**Hints to Consider**:
- Loop through all channel arguments
- Send response for each channel subscribed
- Increment subscription count per channel

---

### 3.3 Enter Subscribed Mode

**Goal**: Restrict commands available in subscribed mode.

**Learning Objectives**:
- Understand connection modes
- Learn about command filtering
- Practice state-based behavior

**Tasks**:
1. Mark connection as "subscribed" after SUBSCRIBE
2. Only allow pub/sub commands: SUBSCRIBE, UNSUBSCRIBE, PSUBSCRIBE, PUNSUBSCRIBE, PING, QUIT
3. Reject other commands with error
4. Test: Try SET after SUBSCRIBE (should fail)

**Hints to Consider**:
- Add boolean flag to client connection state
- Check flag before processing commands
- Return error: `-ERR only (P)SUBSCRIBE / (P)UNSUBSCRIBE / PING / QUIT allowed`

---

### 3.4 PING in Subscribed Mode

**Goal**: Allow PING in subscribed mode.

**Learning Objectives**:
- Understand keep-alive in pub/sub
- Learn about special command handling
- Practice conditional response format

**Tasks**:
1. Allow PING command in subscribed mode
2. Return different format: array instead of simple string
3. Response: `*2\r\n$4\r\npong\r\n$0\r\n\r\n`
4. Test: Subscribe, then send PING

**Hints to Consider**:
- PING in subscribed mode returns array [pong, ""]
- Normal mode PING returns simple string "+PONG"
- Check subscribed mode flag to determine response format

---

### 3.5 Publish a Message

**Goal**: Implement PUBLISH command.

**Learning Objectives**:
- Understand message publishing
- Learn about channel lookup
- Practice message delivery

**Tasks**:
1. Implement PUBLISH command: `PUBLISH <channel> <message>`
2. Find all subscribers to channel
3. Count subscribers (return as integer)
4. Don't deliver messages yet (next task)
5. Test: `PUBLISH news "Hello"`

**Response**:
- Integer: number of clients that received the message
- `:2\r\n` (2 clients received it)

**Hints to Consider**:
- Look up channel in subscribers dictionary
- Count subscribers in that channel
- Return count even if not delivered yet

---

### 3.6 Deliver Messages

**Goal**: Actually deliver published messages to subscribers.

**Learning Objectives**:
- Implement message broadcasting
- Learn about push messages
- Practice async message delivery

**Tasks**:
1. For each subscriber of channel, send message
2. Message format: array [message, channel, payload]
3. Send asynchronously to all subscribers
4. Handle subscriber disconnections gracefully
5. Test: Client A subscribes, Client B publishes, verify A receives

**Message Format to Subscriber**:
```
*3
$7
message
$4
news
$5
Hello
```

**Hints to Consider**:
- Look up all subscribers for channel
- Send message to each subscriber's socket
- Don't block publisher waiting for subscribers
- Use Task.WhenAll for concurrent delivery

---

### 3.7 Unsubscribe

**Goal**: Implement UNSUBSCRIBE command.

**Learning Objectives**:
- Understand subscription lifecycle
- Learn about cleanup operations
- Practice state management

**Tasks**:
1. Implement UNSUBSCRIBE command: `UNSUBSCRIBE [channel...]`
2. Remove client from channel subscriber lists
3. If no channels specified, unsubscribe from all
4. Return confirmation for each channel
5. Exit subscribed mode if no subscriptions remain
6. Test: SUBSCRIBE, then UNSUBSCRIBE

**Response Format**:
```
*3
$11
unsubscribe
$4
news
:0
```
(type, channel, remaining subscription count)

**Hints to Consider**:
- Remove from channel -> subscribers mapping
- Remove from client -> channels mapping
- If subscription count reaches 0, exit subscribed mode
- Handle unsubscribe with no args (unsubscribe all)

---

## Stage 4: Sorted Sets

Sorted sets are Redis data structures that associate members (strings) with scores (floats). Members are unique, but scores can repeat. They're kept sorted by score.

### 4.1 Create a Sorted Set

**Goal**: Add data structure for sorted sets.

**Learning Objectives**:
- Understand sorted set data structure
- Learn about score-based sorting
- Practice composite data structures

**Tasks**:
1. Create `SortedSet` class with:
   - Dictionary: member -> score
   - Sorted list: score -> members
2. Add to global storage (similar to dataStore, listStore)
3. Plan for efficient rank and range queries

**Hints to Consider**:
- Need both O(1) score lookup and O(log n) range queries
- Consider: SortedDictionary or custom skip list
- Members must be unique
- Scores are doubles (floats)

---

### 4.2 Add Members (ZADD)

**Goal**: Implement ZADD command.

**Learning Objectives**:
- Understand sorted set insertion
- Learn about score updates
- Practice sorted insertion

**Tasks**:
1. Implement: `ZADD key score member [score member ...]`
2. Add/update members with scores
3. Maintain sort order
4. Return count of new members added (not updated)
5. Test: `ZADD leaderboard 100 Alice 200 Bob`

**Hints to Consider**:
- Can add multiple score-member pairs in one command
- If member exists, update its score
- Return only count of NEW members added
- Scores can be integers or floats

---

### 4.3 Retrieve Member Rank (ZRANK)

**Goal**: Implement ZRANK command to get member's rank.

**Learning Objectives**:
- Understand rank concept (0-based position)
- Learn about ordered traversal
- Practice binary search or counting

**Tasks**:
1. Implement: `ZRANK key member`
2. Find member's position in sorted order (0-based)
3. Return rank as integer
4. Return nil if member doesn't exist
5. Test: `ZRANK leaderboard Alice`

**Hints to Consider**:
- Rank 0 = lowest score
- Need to count how many members have lower scores
- Handle ties: members with same score sorted lexicographically
- Return `$-1\r\n` if not found

---

### 4.4 List Sorted Set Members (ZRANGE)

**Goal**: Implement ZRANGE command.

**Learning Objectives**:
- Understand range queries
- Learn about inclusive ranges
- Practice slice operations

**Tasks**:
1. Implement: `ZRANGE key start stop [WITHSCORES]`
2. Return members in score order (start to stop, inclusive)
3. Support WITHSCORES option (interleave scores)
4. Indices are 0-based
5. Test: `ZRANGE leaderboard 0 2`

**Response Without WITHSCORES**:
```
*3
$5
Alice
$3
Bob
$7
Charlie
```

**Response With WITHSCORES**:
```
*6
$5
Alice
$3
100
$3
Bob
$3
200
...
```

**Hints to Consider**:
- Similar to LRANGE for lists
- Return members in sorted order by score
- WITHSCORES doubles the response size
- Handle out-of-range indices gracefully

---

### 4.5 ZRANGE with Negative Indexes

**Goal**: Support negative indices in ZRANGE.

**Learning Objectives**:
- Understand negative indexing
- Learn about reverse counting
- Practice index transformation

**Tasks**:
1. Support negative indices: -1 = last, -2 = second-to-last
2. Transform negative to positive indices
3. Return correct range
4. Test: `ZRANGE leaderboard 0 -1` (all members)

**Hints to Consider**:
- If index < 0: actual_index = length + index
- -1 becomes length - 1
- Handle edge cases: -999 for small set

---

### 4.6 Count Sorted Set Members (ZCARD)

**Goal**: Implement ZCARD command.

**Learning Objectives**:
- Understand cardinality concept
- Practice simple queries
- Learn about O(1) operations

**Tasks**:
1. Implement: `ZCARD key`
2. Return count of members in sorted set
3. Return 0 if key doesn't exist
4. Test: `ZCARD leaderboard`

**Hints to Consider**:
- Simply return count from underlying data structure
- Should be O(1) operation
- Return integer: `:5\r\n`

---

### 4.7 Retrieve Member Score (ZSCORE)

**Goal**: Implement ZSCORE command.

**Learning Objectives**:
- Understand score retrieval
- Practice member lookup
- Learn about float formatting

**Tasks**:
1. Implement: `ZSCORE key member`
2. Return member's score as bulk string
3. Return nil if member doesn't exist
4. Test: `ZSCORE leaderboard Alice`

**Response**:
```
$3
100
```

**Hints to Consider**:
- Look up member in dictionary
- Return score as string (bulk string format)
- Return `$-1\r\n` if not found
- Format floats appropriately (handle .0)

---

### 4.8 Remove a Member (ZREM)

**Goal**: Implement ZREM command.

**Learning Objectives**:
- Understand member removal
- Practice cleanup operations
- Learn about multi-member deletion

**Tasks**:
1. Implement: `ZREM key member [member ...]`
2. Remove specified members
3. Maintain sort order of remaining members
4. Return count of members actually removed
5. Test: `ZREM leaderboard Alice Bob`

**Hints to Consider**:
- Can remove multiple members in one command
- Return count of members that existed and were removed
- Remove from both dictionary and sorted structure
- Return integer: `:2\r\n`

---

## Stage 5: Geospatial Commands

Redis geospatial commands allow storing and querying locations by latitude/longitude. Internally uses sorted sets with geohash encoding.

### 5.1 Respond to GEOADD

**Goal**: Parse GEOADD command and return basic response.

**Learning Objectives**:
- Understand geospatial command structure
- Learn about coordinate pairs
- Practice command parsing

**Tasks**:
1. Implement: `GEOADD key longitude latitude member [long lat member ...]`
2. Parse longitude, latitude, and member name
3. Return count of added members (mock for now)
4. Don't store yet (next tasks)
5. Test: `GEOADD locations 13.361389 38.115556 Palermo`

**Hints to Consider**:
- Longitude comes before latitude (lon, lat)
- Arguments come in triplets: lon, lat, member
- Can add multiple locations in one command
- Return integer

---

### 5.2 Validate Coordinates

**Goal**: Validate latitude/longitude ranges.

**Learning Objectives**:
- Understand coordinate constraints
- Learn about input validation
- Practice error handling

**Tasks**:
1. Validate longitude: -180 to 180
2. Validate latitude: -85.05112878 to 85.05112878
3. Return error for invalid coordinates
4. Test with out-of-range values

**Hints to Consider**:
- Redis uses Web Mercator projection (limits latitude)
- Return: `-ERR invalid longitude/latitude`
- Parse as double/float

---

### 5.3 Store a Location

**Goal**: Store geospatial data internally.

**Learning Objectives**:
- Understand geohash encoding
- Learn about sorted set storage
- Practice coordinate transformation

**Tasks**:
1. Convert lon/lat to geohash score
2. Store in sorted set (key -> sorted set of members)
3. Associate member with coordinates
4. Test: Add location, verify stored

**Hints to Consider**:
- Geospatial data stored as sorted set
- Score is geohash-encoded coordinate
- Need to store original lon/lat for retrieval
- Consider separate dictionary: member -> (lon, lat)

---

### 5.4 Calculate Location Score (Geohash)

**Goal**: Implement geohash encoding.

**Learning Objectives**:
- Understand geohash algorithm
- Learn about coordinate encoding
- Practice bit manipulation

**Tasks**:
1. Convert lon/lat to geohash score (52-bit integer)
2. Implement interleaving algorithm
3. Use as sorted set score
4. Test: Verify consistent encoding

**Geohash Algorithm** (simplified):
1. Normalize lon to [0, 1], lat to [0, 1]
2. Convert to binary representations
3. Interleave bits: lon, lat, lon, lat...
4. Result is 52-bit integer

**Hints to Consider**:
- Redis uses geohash for proximity
- Scores allow range queries for nearby points
- Consider using existing geohash library
- Or implement bit interleaving manually

---

### 5.5 Respond to GEOPOS

**Goal**: Implement GEOPOS command to retrieve coordinates.

**Learning Objectives**:
- Understand coordinate retrieval
- Learn about bulk array responses
- Practice multi-member queries

**Tasks**:
1. Implement: `GEOPOS key member [member ...]`
2. Return array of [longitude, latitude] for each member
3. Return nil for non-existent members
4. Test: `GEOPOS locations Palermo Catania`

**Response**:
```
*2
*2
$10
13.361389
$9
38.115556
*2
$10
15.087269
$9
37.502669
```

**Hints to Consider**:
- Need to store original coordinates (not just geohash)
- Return array of arrays
- Each coordinate as bulk string
- Nil for missing members: `*0\r\n`

---

### 5.6 Decode Coordinates

**Goal**: Decode geohash back to lon/lat.

**Learning Objectives**:
- Understand reverse geohash
- Learn about precision loss
- Practice bit extraction

**Tasks**:
1. Extract lon/lat from geohash score
2. De-interleave bits
3. Denormalize to actual coordinates
4. Verify round-trip accuracy

**Hints to Consider**:
- Reverse of encoding process
- Some precision loss is expected
- Extract alternating bits
- Denormalize from [0, 1] to actual ranges

---

### 5.7 Calculate Distance (GEODIST)

**Goal**: Implement GEODIST command.

**Learning Objectives**:
- Understand haversine formula
- Learn about great-circle distance
- Practice mathematical computations

**Tasks**:
1. Implement: `GEODIST key member1 member2 [unit]`
2. Calculate distance between two members
3. Support units: m, km, mi, ft
4. Return distance as bulk string
5. Test: `GEODIST locations Palermo Catania km`

**Haversine Formula**:
```
a = sin²(Δlat/2) + cos(lat1) * cos(lat2) * sin²(Δlon/2)
c = 2 * atan2(√a, √(1−a))
d = R * c
```
Where R = Earth's radius (6371 km)

**Hints to Consider**:
- Need to retrieve coordinates for both members
- Convert degrees to radians for calculations
- Apply haversine formula
- Convert result to requested unit
- Return as bulk string: `$6\r\n166.27\r\n`

---

### 5.8 Search Within Radius (GEORADIUS)

**Goal**: Implement GEORADIUS command (basic version).

**Learning Objectives**:
- Understand proximity queries
- Learn about radius searches
- Practice filtering and sorting

**Tasks**:
1. Implement: `GEORADIUS key longitude latitude radius unit`
2. Find all members within radius of given point
3. Return array of members
4. Optional: Support WITHDIST, WITHCOORD, ASC/DESC
5. Test: `GEORADIUS locations 15 37 100 km`

**Hints to Consider**:
- Use geohash score ranges for initial filtering (optimization)
- Calculate actual distance for each candidate
- Filter by radius
- Sort by distance if needed
- Return array of bulk strings

---

## Stage 6: Lists (Extended)

Lists are ordered collections of strings, sorted by insertion order. Redis lists are implemented as linked lists.

**Note**: Basic list operations (RPUSH, LRANGE) are already implemented. These tasks extend the functionality.

### 6.1 Create a List

**Goal**: Formalize list creation and validation.

**Learning Objectives**:
- Understand list initialization
- Learn about type checking
- Practice defensive programming

**Tasks**:
1. Ensure lists are created only by list commands
2. Add type checking (prevent using string key as list)
3. Return appropriate type errors
4. Test: Try LPUSH on existing string key

**Hints to Consider**:
- Already have basic RPUSH implementation
- Need to prevent type conflicts
- Return: `-WRONGTYPE Operation against a key holding the wrong kind of value`

---

### 6.2 Append an Element (RPUSH - Enhanced)

**Goal**: Enhance existing RPUSH implementation.

**Learning Objectives**:
- Review existing code
- Add robustness
- Practice refactoring

**Tasks**:
1. Review current RPUSH implementation
2. Add error handling for edge cases
3. Ensure atomic operations
4. Test with concurrent clients

**Hints to Consider**:
- Already implemented in Server.cs
- Focus on edge cases and error handling
- Ensure thread-safety with ConcurrentDictionary

---

### 6.3 Append Multiple Elements

**Goal**: Verify RPUSH handles multiple elements correctly.

**Learning Objectives**:
- Understand variadic arguments
- Practice batch operations
- Learn about atomic bulk inserts

**Tasks**:
1. Test: `RPUSH mylist a b c d e`
2. Verify all elements appended in order
3. Return correct count
4. Test: Verify order with LRANGE

**Hints to Consider**:
- Already supported in current implementation
- Each element appended to end of list
- Return total list length after operation

---

### 6.4 List Elements (Positive Indexes)

**Goal**: Verify LRANGE with positive indices works correctly.

**Learning Objectives**:
- Review range queries
- Practice index handling
- Learn about inclusive ranges

**Tasks**:
1. Test: `LRANGE mylist 0 2`
2. Test: `LRANGE mylist 1 3`
3. Verify inclusive behavior (start and stop included)
4. Test out-of-range indices

**Hints to Consider**:
- Already implemented in Server.cs
- Start and stop are both inclusive
- Out-of-range indices should be clamped

---

### 6.5 List Elements (Negative Indexes)

**Goal**: Verify LRANGE with negative indices works correctly.

**Learning Objectives**:
- Review negative indexing
- Practice index transformation
- Learn about reverse counting

**Tasks**:
1. Test: `LRANGE mylist -3 -1` (last 3 elements)
2. Test: `LRANGE mylist 0 -1` (all elements)
3. Test: `LRANGE mylist -2 -1` (last 2 elements)
4. Verify correct transformation

**Hints to Consider**:
- Already implemented in Server.cs
- -1 = last element, -2 = second-to-last
- Transform: if (index < 0) index = length + index

---

### 6.6 Prepend Elements (LPUSH)

**Goal**: Implement LPUSH command to prepend elements.

**Learning Objectives**:
- Understand list head insertion
- Learn about prepend vs append
- Practice list manipulation

**Tasks**:
1. Implement: `LPUSH key element [element ...]`
2. Insert elements at beginning of list
3. Multiple elements inserted left-to-right (a b c → c b a in list)
4. Return list length after operation
5. Test: `LPUSH mylist first second`

**Hints to Consider**:
- Insert at index 0
- Multiple elements: insert in order (each becomes new head)
- `LPUSH mylist a b c` results in: [c, b, a, ...existing...]
- Return integer: list length

---

### 6.7 Query List Length (LLEN)

**Goal**: Implement LLEN command.

**Learning Objectives**:
- Understand length queries
- Practice O(1) operations
- Learn about simple accessors

**Tasks**:
1. Implement: `LLEN key`
2. Return length of list
3. Return 0 if key doesn't exist
4. Return error if key is not a list
5. Test: `LLEN mylist`

**Hints to Consider**:
- Should be O(1) operation (use Count property)
- Return integer: `:5\r\n`
- Check type before returning length

---

### 6.8 Remove an Element (LREM)

**Goal**: Implement LREM command to remove elements.

**Learning Objectives**:
- Understand list element removal
- Learn about count-based removal
- Practice list traversal and modification

**Tasks**:
1. Implement: `LREM key count element`
2. Remove `count` occurrences of `element`
3. count > 0: remove from head to tail
4. count < 0: remove from tail to head
5. count = 0: remove all occurrences
6. Test: `LREM mylist 2 "hello"`

**Hints to Consider**:
- Return count of removed elements
- Direction depends on sign of count
- Use absolute value for removal limit

---

### 6.9 Remove Multiple Elements

**Goal**: Verify LREM handles multiple occurrences correctly.

**Learning Objectives**:
- Practice comprehensive testing
- Understand removal patterns
- Learn about edge cases

**Tasks**:
1. Test list with duplicate values
2. Test: `LREM mylist 0 "value"` (remove all)
3. Test: `LREM mylist -2 "value"` (remove 2 from tail)
4. Verify correct count returned

**Hints to Consider**:
- Track removals as you iterate
- Stop when count reached (unless count = 0)
- Handle case where fewer than count exist

---

### 6.10 Blocking Retrieval (BLPOP)

**Goal**: Implement BLPOP for blocking pop operations.

**Learning Objectives**:
- Understand blocking operations
- Learn about waiting for data
- Practice async coordination

**Tasks**:
1. Implement: `BLPOP key [key ...] timeout`
2. Pop element from first non-empty list
3. Block if all lists empty
4. Return when element available or timeout expires
5. Test: `BLPOP mylist 5`

**Response Format**:
```
*2
$6
mylist
$5
value
```
(key name, popped value)

**Hints to Consider**:
- Timeout in seconds (0 = wait forever)
- Check multiple keys in order
- Use async waiting with timeout
- Return nil if timeout: `*-1\r\n`

---

### 6.11 Blocking Retrieval with Timeout

**Goal**: Verify BLPOP timeout behavior.

**Learning Objectives**:
- Understand timeout handling
- Practice time-based operations
- Learn about nil responses

**Tasks**:
1. Test: `BLPOP empty_list 1` (should timeout)
2. Test: `BLPOP empty_list 0` (wait indefinitely)
3. Verify nil response after timeout
4. Test: Push element while BLPOP is waiting

**Hints to Consider**:
- Return nil array if timeout expires
- Wake up blocked clients when element added
- Handle multiple clients waiting on same list

---

## Stage 7: Streams

Streams are append-only log data structures, like Kafka or event logs. Each entry has a unique ID and fields.

### 7.1 The TYPE Command

**Goal**: Implement TYPE command to check key type.

**Learning Objectives**:
- Understand type system in Redis
- Learn about type introspection
- Practice type detection

**Tasks**:
1. Implement: `TYPE key`
2. Return: string, list, set, zset, hash, stream, none
3. Check which data structure holds the key
4. Test: `TYPE mystring`, `TYPE mylist`

**Response**:
- `+string\r\n` for strings
- `+list\r\n` for lists
- `+none\r\n` for non-existent keys

**Hints to Consider**:
- Check each data store (dataStore, listStore, sortedSetStore, etc.)
- Return as simple string
- Case-insensitive key lookup

---

### 7.2 Create a Stream

**Goal**: Implement basic stream creation with XADD.

**Learning Objectives**:
- Understand stream data structure
- Learn about stream IDs
- Practice structured data storage

**Tasks**:
1. Create `Stream` data structure
2. Implement basic: `XADD key ID field value [field value ...]`
3. Store stream entries with IDs
4. Return the entry ID
5. Test: `XADD mystream * field1 value1`

**Stream Entry Structure**:
- ID: `timestamp-sequence` (e.g., `1526919030474-0`)
- Fields: key-value pairs (like hash)

**Hints to Consider**:
- Stream is ordered collection of entries
- Each entry has unique ID
- ID format: `<milliseconds>-<sequence>`
- `*` means auto-generate ID

---

### 7.3 Validating Entry IDs

**Goal**: Validate and enforce stream ID ordering.

**Learning Objectives**:
- Understand stream ID constraints
- Learn about monotonic IDs
- Practice validation logic

**Tasks**:
1. Validate ID format: `timestamp-sequence`
2. Ensure IDs are strictly increasing
3. Return error if ID not greater than last
4. Test with explicit IDs

**Hints to Consider**:
- IDs must be monotonically increasing
- Compare: first timestamp, then sequence
- Return error: `-ERR The ID specified in XADD is equal or smaller than the target stream top item`

---

### 7.4 Partially Auto-Generated IDs

**Goal**: Support partial ID generation (timestamp-*).

**Learning Objectives**:
- Understand partial auto-generation
- Learn about sequence numbering
- Practice ID completion

**Tasks**:
1. Support: `XADD mystream 1526919030474-* field value`
2. Use provided timestamp, generate sequence
3. Start sequence at 0, increment if same timestamp
4. Test: Multiple entries with same timestamp

**Hints to Consider**:
- Parse timestamp from ID
- If sequence is `*`, generate it
- If timestamp equals last entry, sequence = last_sequence + 1
- Otherwise, sequence = 0

---

### 7.5 Fully Auto-Generated IDs

**Goal**: Support full ID auto-generation (*).

**Learning Objectives**:
- Understand full auto-generation
- Learn about timestamp generation
- Practice ID creation

**Tasks**:
1. Support: `XADD mystream * field value`
2. Generate timestamp from current time (milliseconds)
3. Generate sequence (0 or increment)
4. Return generated ID

**Hints to Consider**:
- Use `DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()`
- If timestamp same as last, increment sequence
- If timestamp greater, sequence = 0
- Handle case: timestamp equal to last but sequence is max

---

### 7.6 Query Entries from Stream (XRANGE)

**Goal**: Implement XRANGE to query stream entries.

**Learning Objectives**:
- Understand range queries on streams
- Learn about ID-based filtering
- Practice entry retrieval

**Tasks**:
1. Implement: `XRANGE key start end [COUNT count]`
2. Return entries with IDs in range [start, end]
3. Format response as array of [ID, [field, value, ...]]
4. Test: `XRANGE mystream 1526919030474-0 1526919030474-5`

**Response Format**:
```
*2
*2
$15
1526919030474-0
*2
$6
field1
$6
value1
*2
$15
1526919030474-1
*2
$6
field2
$6
value2
```

**Hints to Consider**:
- Both start and end are inclusive
- Parse IDs and compare
- Return entries in chronological order

---

### 7.7 Query with - (Minimum ID)

**Goal**: Support `-` as minimum possible ID.

**Learning Objectives**:
- Understand special ID markers
- Learn about unbounded ranges
- Practice edge case handling

**Tasks**:
1. Support: `XRANGE mystream - +` (all entries)
2. Treat `-` as smallest possible ID (0-0)
3. Test: `XRANGE mystream - 1526919030474-5`

**Hints to Consider**:
- `-` represents `0-0`
- Acts as lower bound
- Useful for "from beginning" queries

---

### 7.8 Query with + (Maximum ID)

**Goal**: Support `+` as maximum possible ID.

**Learning Objectives**:
- Understand maximum ID marker
- Complete range query features
- Practice boundary handling

**Tasks**:
1. Support: `XRANGE mystream 1526919030474-0 +`
2. Treat `+` as largest possible ID
3. Test: `XRANGE mystream - +` (all entries)

**Hints to Consider**:
- `+` represents infinity
- Acts as upper bound
- Useful for "to end" queries

---

### 7.9 Query Single Stream using XREAD

**Goal**: Implement XREAD for stream reading.

**Learning Objectives**:
- Understand XREAD semantics
- Learn about read cursors
- Practice stream consumption

**Tasks**:
1. Implement: `XREAD STREAMS key ID`
2. Return entries after specified ID (exclusive)
3. Format similar to XRANGE
4. Test: `XREAD STREAMS mystream 0-0`

**Response Format**:
```
*1
*2
$8
mystream
*2
*2
$15
1526919030474-0
*2
$6
field1
$6
value1
...
```

**Hints to Consider**:
- ID is exclusive (entries AFTER this ID)
- Return array: [[stream_name, [entries]]]
- `0-0` returns all entries

---

### 7.10 Query Multiple Streams using XREAD

**Goal**: Support reading from multiple streams.

**Learning Objectives**:
- Handle multiple stream queries
- Learn about parallel stream reading
- Practice complex response formatting

**Tasks**:
1. Support: `XREAD STREAMS key1 key2 ID1 ID2`
2. Return entries from all streams
3. Each stream paired with its starting ID
4. Test: `XREAD STREAMS s1 s2 0-0 0-0`

**Hints to Consider**:
- STREAMS keyword followed by stream names, then IDs
- Count must match: N streams, N IDs
- Return array of [stream_name, entries] pairs

---

### 7.11 Blocking Reads (XREAD BLOCK)

**Goal**: Implement blocking XREAD.

**Learning Objectives**:
- Understand blocking stream reads
- Learn about stream notifications
- Practice async blocking

**Tasks**:
1. Support: `XREAD BLOCK milliseconds STREAMS key ID`
2. Block if no new entries available
3. Return when new entry added or timeout
4. Test: `XREAD BLOCK 1000 STREAMS mystream $`

**Hints to Consider**:
- BLOCK 0 = wait forever
- Wake up when new entry added to stream
- Return nil if timeout expires

---

### 7.12 Blocking Reads without Timeout

**Goal**: Support infinite blocking (BLOCK 0).

**Learning Objectives**:
- Understand indefinite waiting
- Handle connection-held-open scenarios
- Practice long-lived operations

**Tasks**:
1. Test: `XREAD BLOCK 0 STREAMS mystream $`
2. Wait indefinitely for new entry
3. Test: Add entry from another client (should unblock)

**Hints to Consider**:
- BLOCK 0 = no timeout
- Must wake up when entry added
- Handle client disconnection gracefully

---

### 7.13 Blocking Reads using $

**Goal**: Support `$` as "latest ID" marker.

**Learning Objectives**:
- Understand special $ marker
- Learn about tail reading
- Practice cursor semantics

**Tasks**:
1. Support: `XREAD STREAMS mystream $`
2. `$` means "IDs greater than current last entry"
3. Useful for waiting for NEW entries only
4. Test: `XREAD BLOCK 1000 STREAMS mystream $`

**Hints to Consider**:
- `$` = current maximum ID in stream
- Only return entries added AFTER the command is issued
- Common pattern for tailing streams

---

## Stage 8: Transactions

Transactions allow executing multiple commands atomically. Commands are queued and executed together.

### 8.1 The INCR Command (1/3) - Basic Implementation

**Goal**: Implement INCR command for integers.

**Learning Objectives**:
- Understand atomic increment
- Learn about string-to-integer conversion
- Practice value type handling

**Tasks**:
1. Implement: `INCR key`
2. Increment integer value by 1
3. Initialize to 0 if key doesn't exist
4. Return new value
5. Test: `INCR counter`

**Hints to Consider**:
- Store as string in dataStore
- Parse to int, increment, store back
- Return integer: `:1\r\n`
- Handle expiry (reset if expired)

---

### 8.2 The INCR Command (2/3) - Error Handling

**Goal**: Add error handling for non-integer values.

**Learning Objectives**:
- Understand type constraints
- Learn about error messages
- Practice defensive programming

**Tasks**:
1. Return error if value is not an integer
2. Test: `SET key "hello"` then `INCR key`
3. Return: `-ERR value is not an integer or out of range`

**Hints to Consider**:
- Try parsing with `int.TryParse()`
- If parse fails, return error
- Check before incrementing

---

### 8.3 The INCR Command (3/3) - Concurrency

**Goal**: Ensure INCR is thread-safe.

**Learning Objectives**:
- Understand race conditions
- Learn about atomic operations
- Practice concurrent programming

**Tasks**:
1. Test with multiple clients incrementing simultaneously
2. Ensure no increments are lost
3. Verify final count is correct
4. Consider using Interlocked.Increment or locking

**Hints to Consider**:
- ConcurrentDictionary alone not enough
- Need atomic read-modify-write
- Consider: lock statement or Interlocked operations
- Store as CacheEntry with integer value

---

### 8.4 The MULTI Command

**Goal**: Implement MULTI to start transaction.

**Learning Objectives**:
- Understand transaction begin
- Learn about connection state
- Practice mode switching

**Tasks**:
1. Implement: `MULTI`
2. Enter transaction mode for this client
3. Return: `+OK\r\n`
4. Mark client connection as "in transaction"
5. Test: `MULTI`

**Hints to Consider**:
- Add boolean flag to client connection state
- Initialize empty command queue
- All subsequent commands queued until EXEC

---

### 8.5 The EXEC Command

**Goal**: Implement EXEC to execute transaction.

**Learning Objectives**:
- Understand atomic execution
- Learn about command batching
- Practice transaction completion

**Tasks**:
1. Implement: `EXEC`
2. Execute all queued commands atomically
3. Return array of results
4. Clear queue and exit transaction mode
5. Test: `MULTI`, `SET key val`, `GET key`, `EXEC`

**Response Format**:
```
*2
+OK
$3
val
```
(array of individual command results)

**Hints to Consider**:
- Execute commands in order
- Collect all responses
- Return as array
- Reset transaction state after execution

---

### 8.6 Empty Transaction

**Goal**: Handle EXEC without any commands.

**Learning Objectives**:
- Understand edge cases
- Practice empty batch handling
- Learn about valid empty transactions

**Tasks**:
1. Test: `MULTI` then `EXEC` immediately
2. Return empty array: `*0\r\n`
3. Should not error

**Hints to Consider**:
- Empty queue is valid
- Return empty array
- Still exit transaction mode

---

### 8.7 Queueing Commands

**Goal**: Properly queue commands during transaction.

**Learning Objectives**:
- Understand command buffering
- Learn about deferred execution
- Practice queue management

**Tasks**:
1. After MULTI, queue each command
2. Return `+QUEUED\r\n` for each command
3. Don't execute commands yet
4. Store command and arguments
5. Test: `MULTI`, `SET x 1`, `INCR x`, verify both return QUEUED

**Hints to Consider**:
- Store original command string or parsed parts
- Return QUEUED immediately
- Don't modify data until EXEC
- Commands remain in queue

---

### 8.8 Executing a Transaction

**Goal**: Execute all queued commands atomically.

**Learning Objectives**:
- Understand atomic execution
- Learn about isolation
- Practice batch processing

**Tasks**:
1. On EXEC, process all queued commands
2. Execute in order
3. Collect all responses
4. Return as array
5. Test: Verify all commands executed

**Hints to Consider**:
- Iterate through command queue
- Execute each with ProcessCommand logic
- Build response array
- Clear queue after execution

---

### 8.9 The DISCARD Command

**Goal**: Implement DISCARD to abort transaction.

**Learning Objectives**:
- Understand transaction rollback
- Learn about cancellation
- Practice state cleanup

**Tasks**:
1. Implement: `DISCARD`
2. Clear command queue
3. Exit transaction mode
4. Return: `+OK\r\n`
5. Test: `MULTI`, queue commands, `DISCARD`

**Hints to Consider**:
- Clear queue without executing
- Reset transaction flag
- Return OK
- No commands should have executed

---

### 8.10 Failures within Transactions

**Goal**: Handle command errors during EXEC.

**Learning Objectives**:
- Understand error propagation
- Learn about partial execution
- Practice error handling

**Tasks**:
1. If command fails during EXEC, include error in response array
2. Continue executing remaining commands
3. Return mixed array: some OK, some errors
4. Test: `MULTI`, `SET key val`, `INCR key`, `EXEC` (INCR fails)

**Hints to Consider**:
- Redis continues execution even if command fails
- Each command result included in array
- Errors returned as error strings in array
- Transaction is NOT rolled back

---

### 8.11 Multiple Transactions

**Goal**: Support concurrent transactions from different clients.

**Learning Objectives**:
- Understand per-client state
- Learn about isolation
- Practice concurrent transactions

**Tasks**:
1. Test with 2 clients both in transactions
2. Each client has its own queue
3. EXEC on one doesn't affect the other
4. Verify isolation between clients

**Hints to Consider**:
- Each client connection has its own transaction state
- Queues are per-connection
- No locking between transactions (Redis is single-threaded for command execution)
- Your implementation may need careful concurrency handling

---

## 🎯 Testing Strategy

For each stage:
1. **Unit test**: Test command in isolation with `redis-cli`
2. **Integration test**: Test interaction between commands
3. **Edge cases**: Test boundaries, errors, empty states
4. **Concurrency**: Test with multiple clients if relevant
5. **Performance**: Check with large datasets where applicable

---

## 📚 Learning Resources

- **RESP Protocol**: https://redis.io/docs/reference/protocol-spec/
- **Redis Commands**: https://redis.io/commands/
- **RDB Format**: https://github.com/sripathikrishnan/redis-rdb-tools/wiki/Redis-RDB-Dump-File-Format
- **Replication**: https://redis.io/docs/management/replication/
- **Geospatial**: https://redis.io/docs/data-types/geospatial/

---

## 💡 Pro Tips

1. **Start Small**: Implement the simplest version first, then add features
2. **Test Often**: Use `redis-cli` after each implementation
3. **Read Redis Source**: When stuck, check Redis source code (C, but readable)
4. **Use Debugger**: Step through RESP parsing to understand protocol
5. **Ask for Hints**: Remember the learning-first approach—ask questions!
6. **Incremental Progress**: Each task builds on previous knowledge
7. **Understand Before Coding**: Read Redis docs for each command first

---

## ✅ Progress Tracking

Mark tasks as you complete them:
- [ ] Task not started
- [🚧] Task in progress
- [✅] Task completed
- [🧪] Task needs testing
- [📚] Task needs review

---

Good luck with your Redis implementation journey! Remember: the goal is learning, not just completing. Take time to understand each concept. 🚀
