unit Iocp.Boost;

interface

  uses IdWinsock2, IdWship6;



procedure InitializeStubsEx;

implementation

procedure InitializeStubsEx;
var
  LSocket: TSocket;
begin
//  LSocket := WSASocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, nil, 0, WSA_FLAG_OVERLAPPED);
//  try
//    @AcceptEx := FixupStubEx(LSocket, 'AcceptEx', WSAID_ACCEPTEX);
//    @GetAcceptExSockaddrs := FixupStubEx(LSocket, 'GetAcceptExSockaddrs', WSAID_GETACCEPTEXSOCKADDRS); {Do not localize}
//    @ConnectEx := FixupStubEx(LSocket, 'ConnectEx', WSAID_CONNECTEX); {Do not localize}
//    @DisconnectEx := FixupStubEx(LSocket, 'DisconnectEx', WSAID_DISCONNECTEX); {Do not localize}
//    @WSARecvMsg := FixupStubEx(LSocket, 'WSARecvMsg', WSAID_WSARECVMSG); {Do not localize}
//    @WSARecvMsg := FixupStubEx(LSocket, 'WSARecvMsg', WSAID_WSARECVMSG); {Do not localize}
//    @TransmitFile := FixupStubEx(LSocket, 'TransmitFile', WSAID_TRANSMITFILE); {Do not localize}
//    @TransmitPackets := FixupStubEx(LSocket, 'TransmitPackets', WSAID_TRANSMITPACKETS); {Do not localize}
//
//    {$IFNDEF WINCE}
////    @WSASendMsg := FixupStubEx(LSocket, 'WSASendMsg', WSAID_WSASENDMSG); {Do not localize}
////    @WSAPoll := FixupStubEx(LSocket, 'WSAPoll', WSAID_WSAPOLL); {Do not localize}
//    {$ENDIF}
//  finally
//    closesocket(LSocket);
//  end;
end;


initialization

  IdWship6.InitLibrary;
  InitializeStubsEx

finalization

  IdWinsock2.UninitializeWinSock;
  IdWship6.CloseLibrary;


end.
