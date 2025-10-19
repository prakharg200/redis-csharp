using System.Net;
using System.Net.Sockets;
using System.Text;

TcpListener server = new TcpListener(IPAddress.Any, 6379);
server.Start();

while (true)
{
    Socket client = server.AcceptSocket();
    _ = HandleClientAsync(client);
}

static async Task HandleClientAsync(Socket client)
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

static string ProcessCommand(string request)
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
