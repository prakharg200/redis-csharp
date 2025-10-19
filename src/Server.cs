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
        string response = "+PONG\r\n";
        byte[] responseBytes = Encoding.UTF8.GetBytes(response);
        await client.SendAsync(responseBytes, SocketFlags.None);
    }

    client.Close();
}
