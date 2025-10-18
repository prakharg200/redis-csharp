using System.Net;
using System.Net.Sockets;
using System.Text;

TcpListener server = new TcpListener(IPAddress.Any, 6379);
server.Start();

while (true)
{
    Socket client = server.AcceptSocket();

    string response = "+PONG\r\n";
    byte[] responseBytes = Encoding.UTF8.GetBytes(response);
    client.Send(responseBytes);

    client.Close();
}
