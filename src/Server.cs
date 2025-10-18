using System.Net;
using System.Net.Sockets;
using System.Text;

TcpListener server = new TcpListener(IPAddress.Any, 6379);
server.Start();

while (true)
{
    Socket client = server.AcceptSocket();

    byte[] buffer = new byte[1024];

    while (client.Connected)
    {
        int bytesRead = client.Receive(buffer);
        if (bytesRead == 0)
        {
            break;
        }

        string response = "+PONG\r\n";
        byte[] responseBytes = Encoding.UTF8.GetBytes(response);
        client.Send(responseBytes);
    }

    client.Close();
}
