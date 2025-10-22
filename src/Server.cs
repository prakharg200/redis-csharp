using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Collections.Concurrent;

ConcurrentDictionary<string, CacheEntry> dataStore = new ConcurrentDictionary<string, CacheEntry>();
ConcurrentDictionary<string, List<string>> listStore = new ConcurrentDictionary<string, List<string>>();

TcpListener server = new TcpListener(IPAddress.Any, 6379);
server.Start();

while (true)
{
    Socket client = server.AcceptSocket();
    _ = HandleClientAsync(client);
}

async Task HandleClientAsync(Socket client)
{
    while (client.Connected)
    {
        byte[] buffer = new byte[1024];
        int bytesRead = await client.ReceiveAsync(buffer, SocketFlags.None);

        if (bytesRead == 0)
        {
            break;
        }

        string request = Encoding.UTF8.GetString(buffer, 0, bytesRead);

        string response = ProcessCommand(request);

        byte[] responseBytes = Encoding.UTF8.GetBytes(response);
        await client.SendAsync(responseBytes, SocketFlags.None);
    }

    client.Close();
}

string ProcessCommand(string request)
{
    var parts = ParseRESPArray(request);
    if (parts.Count == 0)
    {
        return "-ERR invalid command\r\n";
    }
    string command = parts[0].ToUpperInvariant();

    if (command == "PING")
    {
        return "+PONG\r\n";
    }
    else if (command == "ECHO")
    {
        if (parts.Count < 2)
        {
            return "-ERR wrong number of arguments for 'ECHO' command\r\n";
        }
        return EncodeBulkString(parts[1]);
    }
    else if (command == "SET")
    {
        if (parts.Count < 3)
        {
            return "-ERR wrong number of arguments for 'SET' command\r\n";
        }

        string key = parts[1];
        string value = parts[2];
        DateTime? expiryTime = null;

        if (parts.Count >= 5 && parts[3].ToUpperInvariant() == "PX")
        {
            if (int.TryParse(parts[4], out int milliseconds))
            {
                expiryTime = DateTime.UtcNow.AddMilliseconds(milliseconds);
            }
            else
            {
                return "-ERR invalid PX value\r\n";
            }
        }

        dataStore[key] = new CacheEntry { Value = value, ExpiryTime = expiryTime };  // Store or update
        return "+OK\r\n";
    }
    else if (command == "GET")
    {
        if (parts.Count < 2)
        {
            return "-ERR wrong number of arguments for 'GET' command\r\n";
        }
        string key = parts[1];

        if (dataStore.TryGetValue(key, out var entry))
        {
            if (entry.ExpiryTime.HasValue && entry.ExpiryTime.Value <= DateTime.UtcNow)
            {
                dataStore.TryRemove(key, out _);
                Console.WriteLine($"GET {key} = (expired)");
                return "$-1\r\n";
            }
            return EncodeBulkString(entry.Value);
        }
        return "$-1\r\n";
    }
    else if (command == "RPUSH"){
        if (parts.Count < 3)
        {
            return "-ERR wrong number of arguments for 'RPUSH' command\r\n";
        }

        string listKey = parts[1];
        var list = listStore.GetOrAdd(listKey, _ => new List<string>());
        
        for (int i=2; i < parts.Count; i++)
        {
            string valueToPush = parts[i];
            list.Add(valueToPush);
        }

        return $":{list.Count}\r\n";
    }

    return "-ERR unknown command\r\n";
}

static List<string> ParseRESPArray(string request)
{
    var result = new List<string>();
    var lines = request.Split("\r\n");

    int i = 0;

    if (i >= lines.Length || !lines[i].StartsWith('*'))
    {
        return result;
    }

    i++;

    while (i < lines.Length - 1)
    {
        if (lines[i].StartsWith('$'))
        {
            i++;
            if (i < lines.Length)
            {
                result.Add(lines[i]);
                i++;
            }
        }
        else
        {
            i++;
        }
    }
    return result;
}

static string EncodeBulkString(string value)
{
    return $"${value.Length}\r\n{value}\r\n";
}

class CacheEntry
{
    public string Value { get; set; }
    public DateTime? ExpiryTime { get; set; }
}
