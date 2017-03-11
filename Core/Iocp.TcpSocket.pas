unit Iocp.TcpSocket;

{���ڿͻ���Socket�أ�
�ͻ���ʹ��ConnectEx������Socket���ӣ�ֻ���ڷ���������Ͽ�����������Socket���ܱ����ã�
������ɿͻ��˷����DisconnectEx�Ͽ������Socket���ܱ����ã����Կͻ���Ҫ�����Ͽ����ӵĻ�
��ֱ����shutdown��closesocket�Ϳ����ˡ�

��ConnectEx��ʱ���ȴ�Socket���в����Ѿ��ɷ������Ͽ��Ŀ���Socket������о����ã�û�о��½�

--����ǿͻ��˵�Socket���û���

������һ�����Է��֣��ͻ��˵�Socket�����൱���ȶ������Ի���ֱ�ӹر�Socket�ȽϿɿ�

ZY. 2012.01.13

ֱ�ӷ���Socket���ã���Ϊ�����һЩ���ȶ����أ������ܵ������ֲ��Ǻܴ�

ZY. 2012.04.19
}

// �������������أ�������TCP/IP��Nagle�㷨
// Ҳ���ǲ��ܷ��͵����ݿ��Ƿ��������ײ�Ļ��壬��ֱ�ӷ���ȥ
// ���һ���̶Ƚ��ͷ���Ч�ʣ������������Ӧ�ٶ�
//{$define __TCP_NODELAY__}

// ���ͻ���0��������������ʱֱ��ʹ�ó����趨�Ļ��棬���ÿ�����Socket�ײ㻺��
{$define __TCP_SNDBUF_ZERO_COPY__}

// ���ջ���0��������������ʱֱ��ʹ�ó����趨�Ļ��棬���ô�Socket�ײ㻺�濽��
//{$define __TCP_RCVBUF_ZERO_COPY__}

// ���ó�ʱ���ʱ��
{$define __TIME_OUT_TIMER__}

interface

uses
  Windows, Messages, Classes, SysUtils, SyncObjs, Math, System.Generics.Collections,
  Iocp.Winsock2, Iocp.Wship6, Iocp.ApiFix, Iocp.ThreadPool, Iocp.MemoryPool,
  Iocp.ObjectPool, Iocp.Queue,
  {$ifdef __TIME_OUT_TIMER__}
  Iocp.TimerQueue,
  {$endif}
  Iocp.Logger, Iocp.Utils;

const
  SHUTDOWN_FLAG = ULONG_PTR(-1);

  MAX_FREE_HANDLE_DATA_BLOCKS = 512;
  MAX_FREE_IO_DATA_BLOCKS = MAX_FREE_HANDLE_DATA_BLOCKS * 2;
  INIT_ACCEPTEX_NUM = 1;
  NET_CACHE_SIZE = 4 * 1024; // ��Ҫ����4K !!!!!
  FILE_CACHE_SIZE = 64 * 1024;

type
  TAddrUnion = record
    case Integer of
      0: (IPv4: TSockAddrIn);
      1: (IPv6: TSockAddrIn6);
  end;

  TAddrBuffer = record
    Addr: TAddrUnion;
    Extra: array [0..15] of Byte;
  end;

  TAcceptExBuffer = array[0..SizeOf(TAddrBuffer) * 2 - 1] of Byte;

  TPerIoBufUnion = record
    case Integer of
      0: (DataBuf: WSABUF);
      // ���Bufferֻ����AcceptEx�����ն˵�ַ���ݣ���СΪ2����ַ�ṹ
      1: (AcceptExBuffer: TAcceptExBuffer);
  end;

  TIocpOperationType = (iotReadZero, iotRead, iotWrite, iotAccept, iotConnect, iotDisconnect);

  {
    *** ��IO���ݽṹ
    ÿ��IO��������Ҫ����һ���ýṹ���ݸ�IOCP
  }
  PIocpPerIoData = ^TIocpPerIoData;
  TIocpPerIoData = record
    Overlapped: TWSAOverlapped;
    Buffer: TPerIoBufUnion;
    Operation: TIocpOperationType;
    ListenSocket, ClientSocket: TSocket;

    BytesTransfered: Cardinal;
  end;

  EIocpTcpException = class(Exception);

  TIocpTcpSocket = class;
  TConnectionSource = (csAccept, csConnect);

  {
     *** Socket ���� ***
  }
  TIocpSocketConnection = class(TIocpObject)
  private
    FSocket: TSocket;
    FRemoteIP: string;
    FRemotePort: Word;
    FConnected: Boolean;

    FRefCount: Integer;
    FDisconnected: Integer;
    FFirstTick, FLastTick: DWORD;
    FTag: Pointer;
    FSndBufSize, FRcvBufSize: Integer;
    FRcvBuffer: Pointer;
    FPendingSend: Integer;
    FPendingRecv: Integer;
    FIsIPv6: Boolean;
    FConnectionSource: TConnectionSource;
    {$IFDEF __TIME_OUT_TIMER__}
    FTimer: PTimer;
    FTimeout: DWORD;
    FLife: DWORD;
    // ���ӳ�ʱ���
    procedure OnTimerExecute;
    {$ENDIF}

    function GetRefCount: Integer;
    function GetIsClosed: Boolean;
    function GetOwner: TIocpTcpSocket;

    function InitSocket: Boolean;
    procedure UpdateTick;

    function ErrorIsNorma(Err: Integer): Boolean;

    procedure IncPendingRecv; inline;
    procedure DecPendingRecv; inline;
    function GetPendingRecv: Integer; inline;

    function PostReadZero: Boolean;
    function PostRead: Boolean;

    procedure IncPendingSend; inline;
    procedure DecPendingSend; inline;
    function GetPendingSend: Integer; inline;

    function _Send(Buf: Pointer; Size: Integer): Integer; virtual;
    procedure _CloseSocket;
  protected
    procedure Initialize; override;
    procedure Finalize; override;

    function PostWrite(const Buf: Pointer; Size: Integer): Boolean; virtual;

    procedure TriggerConnected; virtual;
    procedure TriggerDisconnected; virtual;
    procedure TriggerRecvData(Buf: Pointer; Len: Integer); virtual;
    procedure TriggerSentData(Buf: Pointer; Len: Integer); virtual;

    {$IFDEF __TIME_OUT_TIMER__}
    procedure TriggerTimeout; virtual;
    procedure TriggerLifeout; virtual;
    {$ENDIF}

    function GetIsIdle: Boolean; virtual;
  public
    constructor Create(AOwner: TObject); override;
    destructor Destroy; override;

    function AddRef: Integer;
    function Release: Boolean;
    procedure Disconnect;

    // ���첽����
    function Send(Buf: Pointer; Size: Integer): Integer; overload; virtual;
    function Send(Stream: TStream): Integer; overload; virtual;
    function Send(const Buf; Size: Integer): Integer; overload; inline;
    function Send(const Bytes: TBytes): Integer; overload; inline;
    function Send(const s: RawByteString): Integer; overload; inline;
    function Send(const s: string): Integer; overload; inline;

    property Owner: TIocpTcpSocket read GetOwner;
    property Socket: TSocket read FSocket;
    property RefCount: Integer read GetRefCount;
    property FirstTick: DWORD read FFirstTick;
    property LastTick: DWORD read FLastTick;

    property PeerIP: string read FRemoteIP;
    property PeerAddr: string read FRemoteIP;
    property PeerPort: Word read FRemotePort;
    property IsClosed: Boolean read GetIsClosed;
    property IsIdle: Boolean read GetIsIdle;
    property SndBufSize: Integer read FSndBufSize;
    property RcvBufSize: Integer read FRcvBufSize;
    property PendingSend: Integer read GetPendingSend;
    property PendingRecv: Integer read GetPendingRecv;
    property IsIPv6: Boolean read FIsIPv6;
    property ConnectionSource: TConnectionSource read FConnectionSource;
    {$IFDEF __TIME_OUT_TIMER__}
    property Timeout: DWORD read FTimeout write FTimeout;
    property Life: DWORD read FLife write FLife;
    {$ENDIF}
    property Tag: Pointer read FTag write FTag;
  end;

  TIocpSocketConnectionClass = class of TIocpSocketConnection;

  {
    *** Socket�����б� ***
  }
  TIocpSocketConnectionPair = TPair<TSocket, TIocpSocketConnection>;
  TIocpSocketConnectionDictionary = class(TDictionary<TSocket, TIocpSocketConnection>)
  private
    FOwner: TIocpTcpSocket;

    function GetItem(Socket: TSocket): TIocpSocketConnection;
    procedure SetItem(Socket: TSocket; const Value: TIocpSocketConnection);
  public
    constructor Create(AOwner: TIocpTcpSocket); virtual;

    procedure Assign(const Source: TIocpSocketConnectionDictionary);
    function Delete(Socket: TSocket): Boolean;

    property Item[Socket: TSocket]: TIocpSocketConnection read GetItem write SetItem; default;
  end;

  {
    *** IO�����߳� ***
    ������Ҫ�������շ��߳�,��IOCP�̳߳ص���
  }
  TIocpIoThread = class(TThread)
  private
    FOwner: TIocpTcpSocket;
  protected
    procedure Execute; override;
  public
    constructor Create(IocpSocket: TIocpTcpSocket); reintroduce;
  end;

  {
    *** Accept�߳� ***
    ������AcceptEx�׽��ֲ���ʱ�����µ��׽���
    ���ͬʱ���Դ��� WSA_MAXIMUM_WAIT_EVENTS - 2 (62) ������
  }
  TIocpAcceptThread = class(TThread)
  private const
    MAX_LISTEN_SOCKETS = WSA_MAXIMUM_WAIT_EVENTS - 2;
    EVENT_NEW_LISTEN = 0;
    EVENT_QUIT = 1;
  private type
    TIocpListenData = record
      Socket: TSocket;
      AiFamily: Integer;
      InitAcceptNum: Integer;
      AcceptEvent: THandle;
    end;

    TIocpListenList = TList<TIocpListenData>;
    TIocpEvents = TArray<THandle>;
  private
    FOwner: TIocpTcpSocket;
    FLocker: TCriticalSection;
    FListenList: TIocpListenList;
    FSysEvents, FAllEvents: TIocpEvents;

    procedure Cleanup;
  protected
    procedure Execute; override;
  public
    constructor Create(IocpSocket: TIocpTcpSocket); reintroduce;
    destructor Destroy; override;

    function NewListen(ListenSocket: TSocket; AiFamily, InitAcceptNum: Integer): Boolean;
    function StopListen(ListenSocket: TSocket): Boolean;
    function ListenCount: Integer;
    procedure Reset;
    procedure Quit;
  end;

  TIocpNotifyEvent = procedure(Sender: TObject; Client: TIocpSocketConnection) of object;
  TIocpDataEvent = procedure(Sender: TObject; Client: TIocpSocketConnection; Buf: Pointer; Len: Integer) of object;

  {
    *** ��Ҫ��Socketʵ���� ***
  }
  TIocpTcpSocket = class(TComponent)
  private
    FShutdown: Integer;
    FIocpHandle: THandle;
    FIoThreadsNumber: Integer;
    FIoThreads: array of TIocpIoThread;
    FIoThreadHandles: array of THandle;
    FPendingRequest: Integer;
    FConnectionPool: TIocpObjectPool;
    FPerIoDataPool, FIoCachePool, FFileCachePool: TIocpMemoryPool;
    FConnectionList, FIdleConnectionList: TIocpSocketConnectionDictionary;
    FConnectionListLocker: TCriticalSection;
    FAcceptThread: TIocpAcceptThread;
    {$IFDEF __TIME_OUT_TIMER__}
    FTimeout: DWORD;
    FClientLife: DWORD;
    {$ENDIF}
    FMaxClients: Integer;
    FSentBytes, FRecvBytes: Int64;
    FOnClientConnected: TIocpNotifyEvent;
    FOnClientSentData: TIocpDataEvent;
    FOnClientRecvData: TIocpDataEvent;
    FOnClientDisconnected: TIocpNotifyEvent;

    procedure ProcessRequest(Connection: TIocpSocketConnection; PerIoData: PIocpPerIoData; IoThread: TIocpIoThread); virtual;
    procedure ExtractAddrInfo(const Addr: PSockAddr; AddrLen: Integer; out IP: string; out Port: Word);
    function GetConnectionFreeMemory: Integer;
    function GetConnectionUsedMemory: Integer;
    function GetPerIoFreeMemory: Integer;
    function GetPerIoUsedMemory: Integer;
    function GetConnectionClass: TIocpSocketConnectionClass;
    procedure SetConnectionClass(const Value: TIocpSocketConnectionClass);
    function GetIoCacheFreeMemory: Integer;
    function GetIoCacheUsedMemory: Integer;

    function AllocConnection(Socket: TSocket; Source: TConnectionSource): TIocpSocketConnection;
    procedure FreeConnection(Connection: TIocpSocketConnection);
    function AllocIoData(Socket: TSocket; Operation: TIocpOperationType): PIocpPerIoData;
    procedure FreeIoData(PerIoData: PIocpPerIoData);

    function AssociateSocketWithCompletionPort(Socket: TSocket; Connection: TIocpSocketConnection): Boolean;
    function PostNewAcceptEx(ListenSocket: TSocket; AiFamily: Integer): Boolean;
    procedure TrackSocketStatus(Socket: TSocket);
    function IsShutdown: Boolean;

    procedure RequestAcceptComplete(PerIoData: PIocpPerIoData);
    procedure RequestConnectComplete(Connection: TIocpSocketConnection);
    procedure RequestDisconnectComplete(Connection: TIocpSocketConnection);
    procedure RequestReadZeroComplete(Connection: TIocpSocketConnection; PerIoData: PIocpPerIoData);
    procedure RequestReadComplete(Connection: TIocpSocketConnection; PerIoData: PIocpPerIoData);
    procedure RequestWriteComplete(Connection: TIocpSocketConnection; PerIoData: PIocpPerIoData);
  protected
    function ProcessMessage: Boolean;
    procedure MessagePump;

    procedure StartupWorkers; virtual;
    procedure ShutdownWorkers; virtual;

    // �������漸����������ʵ����IO�¼�����ʱ����Ӧ����
    // ���ӽ���ʱ����
    procedure TriggerClientConnected(Client: TIocpSocketConnection); virtual;

    // ���ӶϿ�ʱ����
    procedure TriggerClientDisconnected(Client: TIocpSocketConnection); virtual;

    // ���յ�����ʱ����
    procedure TriggerClientRecvData(Client: TIocpSocketConnection; Buf: Pointer; Len: Integer); virtual;

    // �����������ʱ����
    // ����Bufֻ��ָ�뱾���ǿ��԰�ȫʹ�õģ�����ָ����ڴ����ݺ��п����Ѿ����ͷ���
    // ����ǧ��Ҫ������¼���ȥ���Է���Buf��ָ�������
    procedure TriggerClientSentData(Client: TIocpSocketConnection; Buf: Pointer; Len: Integer); virtual;
  public
    constructor Create(AOwner: TComponent); overload; override;
    constructor Create(AOwner: TComponent; IoThreadsNumber: Integer); reintroduce; overload; virtual;
    destructor Destroy; override;

    // Host����Ϊ''ʱ�����ϵͳ֧��IPv6���ͬʱ����IPv4��IPv6
    // ::1 = 127.0.0.1
    // :: = 0.0.0.0
    // Port��Ϊ0ʱ����ϵͳ�Զ���������˿ڣ�����ֵ����ʵ�ʵĶ˿ں�
    function Listen(const Host: string; Port: Word; InitAcceptNum: Integer): Word; overload;
    function Listen(Port: Word; InitAcceptNum: Integer): Word; overload;
    procedure StopListen(ListenSocket: TSocket);
    function AsyncConnect(const RemoteAddr: string; RemotePort: Word; Tag: Pointer = nil): TSocket;
    function Connect(const RemoteAddr: string; RemotePort: Word; Tag: Pointer = nil; ConnectTimeout: DWORD = 10000): TIocpSocketConnection;
    procedure DisconnectAll;

    function LockConnectionList: TIocpSocketConnectionDictionary;
    procedure UnlockConnectionList;

    property ConnectionClass: TIocpSocketConnectionClass read GetConnectionClass write SetConnectionClass;
    property ConnectionList: TIocpSocketConnectionDictionary read FConnectionList;
    property IoCachePool: TIocpMemoryPool read FIoCachePool;
    property ConnectionUsedMemory: Integer read GetConnectionUsedMemory;
    property ConnectionFreeMemory: Integer read GetConnectionFreeMemory;
    property PerIoDataPool: TIocpMemoryPool read FPerIoDataPool;
    property PerIoUsedMemory: Integer read GetPerIoUsedMemory;
    property PerIoFreeMemory: Integer read GetPerIoFreeMemory;
    property IoCacheUsedMemory: Integer read GetIoCacheUsedMemory;
    property IoCacheFreeMemory: Integer read GetIoCacheFreeMemory;
    property SentBytes: Int64 read FSentBytes;
    property RecvBytes: Int64 read FRecvBytes;
    property PendingRequest: Integer read FPendingRequest;
  published
    {$IFDEF __TIME_OUT_TIMER__}
    property Timeout: DWORD read FTimeout write FTimeout default 0;
    property ClientLife: DWORD read FClientLife write FClientLife default 0;
    {$ENDIF}
    property MaxClients: Integer read FMaxClients write FMaxClients default 0;
    property IoThreadsNumber: Integer read FIoThreadsNumber write FIoThreadsNumber default 0;
    property OnClientConnected: TIocpNotifyEvent read FOnClientConnected write FOnClientConnected;
    property OnClientDisconnected: TIocpNotifyEvent read FOnClientDisconnected write FOnClientDisconnected;
    property OnClientRecvData: TIocpDataEvent read FOnClientRecvData write FOnClientRecvData;
    property OnClientSentData: TIocpDataEvent read FOnClientSentData write FOnClientSentData;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Iocp', [TIocpTcpSocket]);
end;

{ TIocpSocketConnection }

constructor TIocpSocketConnection.Create(AOwner: TObject);
begin
  inherited Create(AOwner);

  FRcvBuffer := Owner.FIoCachePool.GetMemory(False);
end;

destructor TIocpSocketConnection.Destroy;
begin
  Owner.FIoCachePool.FreeMemory(FRcvBuffer);

  inherited Destroy;
end;

function TIocpSocketConnection.AddRef: Integer;
begin
  Result := TInterlocked.Increment(FRefCount);
end;

function TIocpSocketConnection.Release: Boolean;
begin
  Result := (TInterlocked.Decrement(FRefCount) = 0);
  if not Result then Exit;

  _CloseSocket;
  FConnected := False;
  TriggerDisconnected;
  Owner.FreeConnection(Self);
end;

procedure TIocpSocketConnection.Disconnect;
var
  PerIoData: PIocpPerIoData;
begin
  if (TInterlocked.Exchange(FDisconnected, 1) <> 0) then Exit;

  // �������ü���
  // �������1��˵���������ڹر�����
  if (AddRef = 1) then Exit;

  PerIoData := Owner.AllocIoData(FSocket, iotDisconnect);

  // �����Ͽ����ӱ���������Ͽ�Socket��������ܻ����ReadZero����һֱ����
  if not DisconnectEx(FSocket, PWSAOverlapped(PerIoData), 0, 0)
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    Release; // ��Ӧ������ͷ�� AddRef
    _CloseSocket;
    Owner.FreeIoData(PerIoData);

    Release;
  end;
end;

procedure TIocpSocketConnection.DecPendingRecv;
begin
  TInterlocked.Decrement(FPendingRecv);
end;

procedure TIocpSocketConnection.DecPendingSend;
begin
  TInterlocked.Decrement(FPendingSend);
end;

procedure TIocpSocketConnection.Finalize;
begin
  TTimerQueue.RemoveTimer(FTimer);
end;

function TIocpSocketConnection.GetIsClosed: Boolean;
begin
  Result := (TInterlocked.CompareExchange(FDisconnected, 0, 0) = 1);
end;

function TIocpSocketConnection.GetIsIdle: Boolean;
begin
  Result := not GetIsClosed and (FPendingSend = 0) and (FPendingRecv = 0)
end;

function TIocpSocketConnection.GetOwner: TIocpTcpSocket;
begin
  Result := TIocpTcpSocket(inherited Owner);
end;

function TIocpSocketConnection.GetPendingRecv: Integer;
begin
  Result := TInterlocked.CompareExchange(FPendingRecv, 0, 0);
end;

function TIocpSocketConnection.GetPendingSend: Integer;
begin
  Result := TInterlocked.CompareExchange(FPendingSend, 0, 0);
end;

function TIocpSocketConnection.GetRefCount: Integer;
begin
  Result := TInterlocked.CompareExchange(FRefCount, 0, 0);
end;

function TIocpSocketConnection.InitSocket: Boolean;
var
{$IF defined(__TCP_SNDBUF_ZERO_COPY__) or defined(__TCP_RCVBUF_ZERO_COPY__)}
  BufSize: Integer;
{$IFEND}
{$IF not (defined(__TCP_SNDBUF_ZERO_COPY__) and defined(__TCP_RCVBUF_ZERO_COPY__))}
  OptLen: Integer;
{$IFEND}
{$IFDEF __TCP_NODELAY__}
  NagleValue: Byte;
{$ENDIF}
  LAliveIn, LAliveOut: tcp_keepalive;
  LBytesReturn: Cardinal;
begin
  Result := False;

{$IFDEF __TCP_SNDBUF_ZERO_COPY__}
  BufSize := 0;
  if (setsockopt(FSocket, SOL_SOCKET, SO_SNDBUF,
    PAnsiChar(@BufSize), SizeOf(BufSize)) = SOCKET_ERROR) then
  begin
    AppendLog('%s.InitSocket.setsockopt.SO_SNDBUF ERROR %d=%s', [ClassName, WSAGetLastError, SysErrorMessage(WSAGetLastError)], ltWarning);
    Exit;
  end;
  FSndBufSize := Owner.FIoCachePool.BlockSize;
{$ELSE}
  OptLen := SizeOf(FSndBufSize);
  if (getsockopt(FSocket, SOL_SOCKET, SO_SNDBUF,
    PAnsiChar(@FSndBufSize), OptLen) = SOCKET_ERROR) then
  begin
    AppendLog('%s.InitSocket.getsockopt.SO_SNDBUF ERROR %d=%s', [ClassName, WSAGetLastError, SysErrorMessage(WSAGetLastError)], ltWarning);
    Exit;
  end;
{$ENDIF}

{$IFDEF __TCP_RCVBUF_ZERO_COPY__}
  BufSize := 0;
  if (setsockopt(FSocket, SOL_SOCKET, SO_RCVBUF,
    PAnsiChar(@BufSize), SizeOf(BufSize)) = SOCKET_ERROR) then
  begin
    AppendLog('%s.InitSocket.setsockopt.SO_RCVBUF ERROR %d=%s', [ClassName, WSAGetLastError, SysErrorMessage(WSAGetLastError)], ltWarning);
    Exit;
  end;
  FRcvBufSize := Owner.FIoCachePool.BlockSize;
{$ELSE}
  OptLen := SizeOf(FRcvBufSize);
  if (getsockopt(FSocket, SOL_SOCKET, SO_RCVBUF,
    PAnsiChar(@FRcvBufSize), OptLen) = SOCKET_ERROR) then
  begin
    AppendLog('%s.InitSocket.getsockopt.SO_RCVBUF ERROR %d=%s', [ClassName, WSAGetLastError, SysErrorMessage(WSAGetLastError)], ltWarning);
    Exit;
  end;
{$ENDIF}

{$IFDEF __TCP_NODELAY__}
  NagleValue := 1;
  if (setsockopt(FSocket, IPPROTO_TCP, TCP_NODELAY, PAnsiChar(@NagleValue), SizeOf(Byte)) = SOCKET_ERROR) then
  begin
    AppendLog('%s.InitSocket.setsockopt.TCP_NODELAY ERROR %d=%s', [ClassName, WSAGetLastError, SysErrorMessage(WSAGetLastError)], ltWarning);
    Exit;
  end;
{$ENDIF}

  // ����TCP��������
  LAliveIn.onoff := 1;
  LAliveIn.keepalivetime := 10000; // ��ʼ�״�KeepAlive̽��ǰ��TCP�ձ�ʱ��
  LAliveIn.keepaliveinterval := 2000; // ����KeepAlive̽��ļ�� (̽��5�Σ����������TCPЭ���ڲ�����ģ����ܸ���)
  if (WSAIoctl(FSocket, SIO_KEEPALIVE_VALS, @LAliveIn, SizeOf(LAliveIn),
    @LAliveOut, SizeOf(LAliveOut), @LBytesReturn, nil, nil) = SOCKET_ERROR) then
  begin
    AppendLog('%s.InitSocket.SIO_KEEPALIVE_VALS ERROR %d=%s', [ClassName, WSAGetLastError, SysErrorMessage(WSAGetLastError)], ltWarning);
    Exit;
  end;

  Result := True;
end;

function TIocpSocketConnection.ErrorIsNorma(Err: Integer): Boolean;
begin
  Result :=
    (Err = WSAEINTR) or
    (Err = WSAECONNABORTED) or
    (Err = WSAECONNRESET) or
    (Err = WSAESHUTDOWN);
end;

procedure TIocpSocketConnection.IncPendingRecv;
begin
  TInterlocked.Increment(FPendingRecv);
end;

procedure TIocpSocketConnection.IncPendingSend;
begin
  TInterlocked.Increment(FPendingSend);
end;

procedure TIocpSocketConnection.Initialize;
begin
  FSocket := 0;
  FRefCount := 1; // �ó�ʼ���ü��� 1
  FPendingSend := 0;
  FPendingRecv := 0;
  FDisconnected := 0;
  FLastTick := 0;
  FTag := nil;

  FRemoteIP := '';
  FRemotePort := 0;

  FFirstTick := GetTickCount;

  {$IFDEF __TIME_OUT_TIMER__}
  FTimeout := Owner.Timeout;
  FLife := Owner.ClientLife;
  FTimer := TTimerQueue.NewTimer(1000, OnTimerExecute);
  {$ENDIF}
end;

procedure TIocpSocketConnection._CloseSocket;
//var
//	lingerStruct: TLinger;
begin
{	lingerStruct.l_onoff := 1;
  lingerStruct.l_linger := 0;
  setsockopt(FSocket, SOL_SOCKET, SO_LINGER, PAnsiChar(@lingerStruct), SizeOf(lingerStruct));}

  if (FSocket <> 0) then
    Iocp.Winsock2.closesocket(FSocket);
end;

function TIocpSocketConnection._Send(Buf: Pointer; Size: Integer): Integer;
var
  BlockSize: Integer;
begin
  if IsClosed then Exit(-1);

  Result := Size;

  // ��IocpHttpServer��ʵ�ʲ����з��֣���Server���͵Ŀ����4K��ʱ��
  // ������յ��������п��ܻ���ֻ��ң�����������������ｫ���͵���
  // ����ֳ�4K��С�鷢��
  while (Size > 0) do
  begin
    BlockSize := Min(Owner.FIoCachePool.BlockSize, Size);
    if not PostWrite(Buf, BlockSize) then Exit(-2);
    Inc(PAnsiChar(Buf), BlockSize);
    Dec(Size, BlockSize);
  end;
end;

function TIocpSocketConnection.Send(Buf: Pointer; Size: Integer): Integer;
begin
  Result := _Send(Buf, Size);
end;

function TIocpSocketConnection.Send(const Buf; Size: Integer): Integer;
begin
  Result := Send(@Buf, Size);
end;

function TIocpSocketConnection.Send(const Bytes: TBytes): Integer;
begin
  Result := Send(Pointer(Bytes), Length(Bytes));
end;

function TIocpSocketConnection.Send(const s: RawByteString): Integer;
begin
  Result := Send(Pointer(s), Length(s));
end;

function TIocpSocketConnection.Send(const s: string): Integer;
begin
  Result := Send(Pointer(s), Length(s) * SizeOf(Char));
end;

function TIocpSocketConnection.Send(Stream: TStream): Integer;
var
  Buf: Pointer;
  BufSize, BlockSize: Integer;
begin
  BufSize := Owner.FFileCachePool.BlockSize;
  Buf := Owner.FFileCachePool.GetMemory(False);
  try
    Stream.Position := 0;
    while True do
    begin
      BlockSize := Stream.Read(Buf^, BufSize);
      if (BlockSize = 0) then Break;

      if (_Send(Buf, BlockSize) < 0) then Exit(-1);
    end;

    Result := Stream.Size;
  finally
    Owner.FFileCachePool.FreeMemory(Buf);
  end;
end;

{$IFDEF __TIME_OUT_TIMER__}
procedure TIocpSocketConnection.OnTimerExecute;
begin
  try
    if IsClosed then Exit;

    // ��ʱ,�Ͽ�����
    if (FTimeout > 0) and (FLastTick > 0) and (CalcTickDiff(FLastTick, GetTickCount) > FTimeout) then
    begin
      TriggerTimeout;
      Disconnect;
      Exit;
    end;

    // ����������,�Ͽ�����
    if (FLife > 0) and (FFirstTick > 0) and (CalcTickDiff(FFirstTick, GetTickCount) > FLife) then
    begin
      TriggerLifeout;
      Disconnect;
      Exit;
    end;
  except
  end;
end;

procedure TIocpSocketConnection.TriggerTimeout;
begin
end;

procedure TIocpSocketConnection.TriggerLifeout;
begin
end;
{$ENDIF}

procedure TIocpSocketConnection.TriggerConnected;
begin
  FConnected := True;
  Owner.TriggerClientConnected(Self);
end;

procedure TIocpSocketConnection.TriggerDisconnected;
begin
  Owner.TriggerClientDisconnected(Self);
end;

procedure TIocpSocketConnection.TriggerRecvData(Buf: Pointer; Len: Integer);
begin
  Owner.TriggerClientRecvData(Self, Buf, Len);
end;

procedure TIocpSocketConnection.TriggerSentData(Buf: Pointer; Len: Integer);
begin
  Owner.TriggerClientSentData(Self, Buf, Len);
end;

function TIocpSocketConnection.PostReadZero: Boolean;
var
  PerIoData: PIocpPerIoData;
  Bytes, Flags: Cardinal;
  LastErr: Integer;
begin
  Result := False;
  if IsClosed then Exit;

  // �������ü���
  // �������1��˵���������ڹر�����
  if (AddRef = 1) then Exit;

  PerIoData := Owner.AllocIoData(FSocket, iotReadZero);
  PerIoData.Buffer.DataBuf.Buf := nil;
  PerIoData.Buffer.DataBuf.Len := 0;
  Flags := 0;
  Bytes := 0;
  if (WSARecv(PerIoData.ClientSocket, @PerIoData.Buffer.DataBuf, 1, Bytes, Flags, PWSAOverlapped(PerIoData), nil) = SOCKET_ERROR)
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    LastErr := WSAGetLastError;
    if not ErrorIsNorma(LastErr) then
    begin
      AppendLog('%s.Socket%d PostReadZero.WSARecv ERROR %d=%s', [ClassName, FSocket, LastErr, SysErrorMessage(LastErr)], ltWarning);
      Owner.TrackSocketStatus(FSocket);
    end;
    Release; // ��Ӧ������ͷ�� AddRef
    Disconnect; // ��Ӧ���ӳ�ʼ��ʱ�� FRefCount := 1
    Owner.FreeIoData(PerIoData);
    Exit;
  end;

  Result := True;
end;

function TIocpSocketConnection.PostRead: Boolean;
var
  PerIoData: PIocpPerIoData;
  Bytes, Flags: Cardinal;
  LastErr: Integer;
begin
  Result := False;
  if IsClosed then Exit;

  // �������ü���
  // �������1��˵���������ڹر�����
  if (AddRef = 1) then Exit;

  IncPendingRecv;

  PerIoData := Owner.AllocIoData(FSocket, iotRead);
  PerIoData.Buffer.DataBuf.Buf := FRcvBuffer;
  PerIoData.Buffer.DataBuf.Len := Owner.FIoCachePool.BlockSize;

  Flags := 0;
  Bytes := 0;
  if (WSARecv(PerIoData.ClientSocket, @PerIoData.Buffer.DataBuf, 1, Bytes, Flags, PWSAOverlapped(PerIoData), nil) = SOCKET_ERROR)
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    LastErr := WSAGetLastError;
    if not ErrorIsNorma(LastErr) then
      AppendLog('%s.Socket%d PostRead.WSARecv ERROR %d=%s', [ClassName, FSocket, LastErr, SysErrorMessage(LastErr)], ltWarning);
    DecPendingRecv;
    Release; // ��Ӧ������ͷ�� AddRef
    Disconnect; // ��Ӧ���ӳ�ʼ��ʱ�� FRefCount := 1
    Owner.FreeIoData(PerIoData);
    Exit;
  end;

  Result := True;
end;

function TIocpSocketConnection.PostWrite(const Buf: Pointer; Size: Integer): Boolean;
var
  PerIoData: PIocpPerIoData;
  Bytes: DWORD;
  LastErr: Integer;
  SndBuf: Pointer;
begin
  if IsClosed then Exit(False);

  // �������ü���
  // �������1��˵���������ڹر�����
  if (AddRef = 1) then Exit(False);

  IncPendingSend;

  SndBuf := Owner.FIoCachePool.GetMemory(False); // ���䷢�ͻ��棬�������֮���ͷ�
  CopyMemory(SndBuf, Buf, Size);

  PerIoData := Owner.AllocIoData(FSocket, iotWrite);
  PerIoData.Buffer.DataBuf.Buf := SndBuf;
  PerIoData.Buffer.DataBuf.Len := Size;

  // WSAEFAULT(10014)
  // The lpBuffers, lpNumberOfBytesSent, lpOverlapped, lpCompletionRoutine parameter
  // is not totally contained in a valid part of the user address space.
  if (WSASend(FSocket, @PerIoData.Buffer.DataBuf, 1, Bytes, 0, PWSAOverlapped(PerIoData), nil) = SOCKET_ERROR)
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    LastErr := WSAGetLastError;
    if not ErrorIsNorma(LastErr) then
      AppendLog('%s.Socket%d PostWrite.WSASend error, ERR=%d,%s', [ClassName, FSocket, LastErr, SysErrorMessage(LastErr)], ltWarning);
    DecPendingSend;
    Release; // ��Ӧ������ͷ�� AddRef
    Disconnect; // ��Ӧ���ӳ�ʼ��ʱ�� FRefCount := 1
    Owner.FreeIoData(PerIoData);
    Owner.FIoCachePool.FreeMemory(SndBuf);
    Exit(False);
  end;

  Result := True;
end;

procedure TIocpSocketConnection.UpdateTick;
begin
  FLastTick := GetTickCount;
end;

{ TIocpSocketConnectionDictionary }

constructor TIocpSocketConnectionDictionary.Create(AOwner: TIocpTcpSocket);
begin
  inherited Create;

  FOwner := AOwner;
end;

procedure TIocpSocketConnectionDictionary.Assign(const Source: TIocpSocketConnectionDictionary);
var
  Pair: TIocpSocketConnectionPair;
begin
  FOwner := Source.FOwner;
  Clear;
  for Pair in Source do
    AddOrSetValue(Pair.Key, Pair.Value);
end;

function TIocpSocketConnectionDictionary.GetItem(Socket: TSocket): TIocpSocketConnection;
begin
  if not TryGetValue(Socket, Result) then
    Result := nil;
end;

procedure TIocpSocketConnectionDictionary.SetItem(Socket: TSocket;
  const Value: TIocpSocketConnection);
begin
  AddOrSetValue(Socket, Value);
end;

function TIocpSocketConnectionDictionary.Delete(Socket: TSocket): Boolean;
begin
  Result := ContainsKey(Socket);
  if Result then
    Remove(Socket);
end;

{ TIocpIoThread }

constructor TIocpIoThread.Create(IocpSocket: TIocpTcpSocket);
begin
  inherited Create(True);

  FOwner := IocpSocket;

  Suspended := False;
end;

procedure TIocpIoThread.Execute;
const
  ERROR_ABANDONED_WAIT_0 = 735;
var
  IocpStatusOk: Boolean;
  BytesTransferred: Cardinal;
  Connection: TIocpSocketConnection;
  PerIoData: PIocpPerIoData;
  LastErr: DWORD;
begin
//  AppendLog('%s.IoThread %d start', [FOwner.ClassName, ThreadID]);
  while not Terminated do
  try
    IocpStatusOk := Iocp.ApiFix.GetQueuedCompletionStatus(FOwner.FIocpHandle,
      BytesTransferred, ULONG_PTR(Connection), POverlapped(PerIoData), WSA_INFINITE);

    {
    (1) ���I/O����(WSASend() / WSARecv())�ɹ����,��ô����ֵΪTRUE,���� lpNumberOfBytes Ϊ�Ѵ��͵��ֽ���.ע��,�Ѵ��͵��ֽ����п���С����������/���յ��ֽ���.
    (2) ����Է��ر����׽���,��ô���������
    (a) I/O�����Ѿ������һ����,����WSASend()������1K�ֽ�,�������е�512�ֽ��Ѿ��������,�򷵻�ֵΪTRUE, lpNumberOfBytes ָ���ֵΪ512, lpOverlapped ��Ч.
    (b) I/O����û�����,��ô����ֵΪFALSE, lpNumberOfBytes ָ���ֵΪ0, lpCompletionKey, lpOverlapped ��Ч.
    (3) ������ǳ����ⷽ�����ر����׽���,���(2)�����һ��,û������.
    (4) �����������������,�򷵻�ֵΪFALSE,���� lpCompletionKey, lpOverlapped = NULL,�����������,Ӧ�õ��� GetLastError() �鿴������Ϣ,�����˳��ȴ�GetQueuedCompletionStatus()��ѭ��.
    }

    if not IocpStatusOk then
    begin
      if (PerIoData = nil) and (Connection = nil) then
      begin
        LastErr := GetLastError;
        //if (LastErr <> ERROR_ABANDONED_WAIT_0) then
          AppendLog('%s IoThread %d ERROR %d=%s', [FOwner.ClassName, ThreadID, LastErr, SysErrorMessage(LastErr)], ltError);
        Break;
      end;

      if (PerIoData <> nil) then
        FOwner.FreeIoData(PerIoData);

      if (Connection <> nil) then
      begin
        Connection.Release; // ��ӦPostRead/PostWrite�е�AddRef
        Connection.Disconnect; // ��Ӧ���Ӵ���ʱ��FRefCount := 1
      end;

      Continue;
    end;

    if (BytesTransferred = 0) and (ULONG_PTR(PerIoData) = SHUTDOWN_FLAG) then Break;
    if (Connection = nil) and (PerIoData = nil) then Continue;

    PerIoData.BytesTransfered := BytesTransferred;
    FOwner.ProcessRequest(Connection, PerIoData, Self);
  except
    on e: Exception do
      AppendLog('TIocpIoThread.Execute ERROR %s=%s', [e.ClassName, e.Message], ltException);
  end;

//  AppendLog('%s.IoThread %d exit', [FOwner.ClassName, ThreadID]);
end;

{ TIocpAcceptThread }

constructor TIocpAcceptThread.Create(IocpSocket: TIocpTcpSocket);
begin
  inherited Create(True);

  FOwner := IocpSocket;
  FLocker := TCriticalSection.Create;
  FListenList := TIocpListenList.Create;
  SetLength(FSysEvents, 2);
  FSysEvents[0] := CreateEvent(nil, True, False, nil); // New listen
  FSysEvents[1] := CreateEvent(nil, True, False, nil); // Quit

  Reset;

  Suspended := False;
end;

destructor TIocpAcceptThread.Destroy;
begin
  FreeAndNil(FListenList);
  FLocker.Free;
  inherited Destroy;
end;

procedure TIocpAcceptThread.Execute;
var
  i: Integer;
  ListenData: TIocpListenData;
  LastErr: Integer;
  RetEvents: TWSANetworkEvents;
  RetCode: DWORD;
begin
  try
    while not Terminated do
    begin
      ResetEvent(FSysEvents[EVENT_NEW_LISTEN]);

      // �ȴ��˳�����ACCEPT�¼�
      RetCode := WSAWaitForMultipleEvents(Length(FAllEvents), @FAllEvents[0], False, INFINITE, True);

      // �յ��˳��¼�֪ͨ
      if (RetCode = WSA_WAIT_EVENT_0 + EVENT_QUIT) or (RetCode = WSA_WAIT_FAILED) or Terminated then Break;

      // ���µļ�������
      if (RetCode = WSA_WAIT_EVENT_0 + EVENT_NEW_LISTEN) then Continue;

      // ȡ����������
      FLocker.Enter;
      ListenData := FListenList[Integer(RetCode) - WSA_WAIT_EVENT_0 - Length(FSysEvents)];
      FLocker.Leave;

      // ��ȡ�¼�״̬
      if (WSAEnumNetworkEvents(ListenData.Socket, ListenData.AcceptEvent, @RetEvents) = SOCKET_ERROR) then
      begin
        LastErr := WSAGetLastError;
        AppendLog('%s.WSAEnumNetworkEvents(Socket=%d), ERROR %d=%s', [ClassName, ListenData.Socket, LastErr, SysErrorMessage(LastErr)], ltWarning);
        Break;
      end;

      // ���ACCEPT�¼���������Ͷ���µ�Accept�׽���
      // ÿ��Ͷ�� FInitAcceptNum ��
      if (RetEvents.lNetworkEvents and FD_ACCEPT = FD_ACCEPT) then
      begin
        if (RetEvents.iErrorCode[FD_ACCEPT_BIT] <> 0) then
        begin
          LastErr := WSAGetLastError;
          AppendLog('%s.WSAEnumNetworkEvents(Socket=%d), ERROR %d=%s', [ClassName, ListenData.Socket, LastErr, SysErrorMessage(LastErr)], ltWarning);
          Break;
        end;

        for i := 1 to ListenData.InitAcceptNum do
          if not FOwner.PostNewAcceptEx(ListenData.Socket, ListenData.AiFamily) then Break;
      end;
    end;

    Cleanup;
  except
    on e: Exception do
      AppendLog('%s.Execute ERROR %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
end;

function TIocpAcceptThread.ListenCount: Integer;
begin
  Result := FListenList.Count;
end;

procedure TIocpAcceptThread.Quit;
begin
  SetEvent(FSysEvents[EVENT_QUIT]);
end;

procedure TIocpAcceptThread.Reset;
  function GetEvents: TIocpEvents;
  var
    i: Integer;
  begin
    SetLength(Result, Length(FSysEvents) + FListenList.Count);
    for i := Low(FSysEvents) to High(FSysEvents) do
      Result[i] := FSysEvents[i];
    FLocker.Enter;
    try
      for i := 0 to FListenList.Count - 1 do
        Result[i + Length(FSysEvents)] := FListenList[i].AcceptEvent;
    finally
      FLocker.Leave;
    end;
  end;
begin
  FAllEvents := GetEvents;
  SetEvent(FSysEvents[EVENT_NEW_LISTEN]);
end;

function TIocpAcceptThread.NewListen(ListenSocket: TSocket; AiFamily,
  InitAcceptNum: Integer): Boolean;
var
  ListenData: TIocpListenData;
  i: Integer;
begin
  FLocker.Enter;
  try
    if (FListenList.Count >= MAX_LISTEN_SOCKETS) then Exit(False);

    ListenData.Socket := ListenSocket;
    ListenData.AiFamily := AiFamily;
    ListenData.InitAcceptNum := InitAcceptNum;
    for i := 1 to InitAcceptNum do
      FOwner.PostNewAcceptEx(ListenSocket, AiFamily);

    ListenData.AcceptEvent := WSACreateEvent;
    WSAEventSelect(ListenSocket, ListenData.AcceptEvent, FD_ACCEPT);
    FListenList.Add(ListenData);
  finally
    FLocker.Leave;
  end;

  Reset;
  Result := True;
end;

function TIocpAcceptThread.StopListen(ListenSocket: TSocket): Boolean;
var
  ListenData: TIocpListenData;
begin
  Result := False;

  FLocker.Enter;
  try
    for ListenData in FListenList do
    begin
      if (ListenData.Socket = ListenSocket) then
      begin
        Iocp.Winsock2.closesocket(ListenData.Socket);
        CloseHandle(ListenData.AcceptEvent);
        FListenList.Remove(ListenData);
        Result := True;
        Break;
      end;
    end;
  finally
    FLocker.Leave;
  end;

  Reset;
end;

procedure TIocpAcceptThread.Cleanup;
var
  ListenData: TIocpListenData;
  Event: THandle;
begin
  FLocker.Enter;
  try
    for ListenData in FListenList do
    begin
      Iocp.Winsock2.closesocket(ListenData.Socket);
      CloseHandle(ListenData.AcceptEvent);
    end;
    FListenList.Clear;
  finally
    FLocker.Leave;
  end;

  for Event in FSysEvents do
    CloseHandle(Event);
  FSysEvents := nil;
  FAllEvents := nil;
end;

{ TIocpTcpSocket }

constructor TIocpTcpSocket.Create(AOwner: TComponent; IoThreadsNumber: Integer);
begin
  inherited Create(AOwner);

  FConnectionPool := TIocpObjectPool.Create(Self, TIocpSocketConnection, MAX_FREE_HANDLE_DATA_BLOCKS);
  FPerIoDataPool := TIocpMemoryPool.Create(SizeOf(TIocpPerIoData), MAX_FREE_IO_DATA_BLOCKS);
  FIoCachePool := TIocpMemoryPool.Create(NET_CACHE_SIZE, MAX_FREE_IO_DATA_BLOCKS);
  FFileCachePool := TIocpMemoryPool.Create(FILE_CACHE_SIZE, MAX_FREE_HANDLE_DATA_BLOCKS);
  FConnectionList := TIocpSocketConnectionDictionary.Create(Self);
  FConnectionListLocker := TCriticalSection.Create;
  FIdleConnectionList := TIocpSocketConnectionDictionary.Create(Self);

  FIoThreadsNumber := IoThreadsNumber;
  FIocpHandle := 0;
  {$IFDEF __TIME_OUT_TIMER__}
  FTimeout := 0;
  FClientLife := 0;
  {$ENDIF}
  FMaxClients := 0;
  StartupWorkers;
end;

constructor TIocpTcpSocket.Create(AOwner: TComponent);
begin
  Create(AOwner, 0);
end;

destructor TIocpTcpSocket.Destroy;
begin
  ShutdownWorkers;

  FConnectionList.Free;
  FConnectionListLocker.Free;
  FIdleConnectionList.Free;
  FConnectionPool.Free;
  FPerIoDataPool.Free;
  FIoCachePool.Free;
  FFileCachePool.Free;

  inherited Destroy;
end;

function TIocpTcpSocket.PostNewAcceptEx(ListenSocket: TSocket; AiFamily: Integer): Boolean;
var
  PerIoData: PIocpPerIoData;
  ClientSocket: TSocket;
  Bytes: Cardinal;
  LastErr: Integer;
  Connection: TIocpSocketConnection;
begin
  Result := False;

  ClientSocket := WSASocket(AiFamily, SOCK_STREAM, IPPROTO_TCP, nil, 0, WSA_FLAG_OVERLAPPED);
  if (ClientSocket = INVALID_SOCKET) then
  begin
    LastErr := WSAGetLastError;
    AppendLog('%s.PostNewAcceptEx.WSASocket, ERROR %d=%s', [ClassName, LastErr, SysErrorMessage(LastErr)], ltWarning);
    Exit;
  end;

  // �����µ����Ӷ���
  Connection := AllocConnection(ClientSocket, csAccept);
  Connection.FIsIPv6 := (AiFamily = AF_INET6);

  // �����ӷŵ����������б���
  // ��ShutdownWorks�в��������ͷ�Socket��Դ����������Socket���й¶
  try
    FConnectionListLocker.Enter;
    FIdleConnectionList[ClientSocket] := Connection;
  finally
    FConnectionListLocker.Leave;
  end;

  PerIoData := AllocIoData(ClientSocket, iotAccept);
  PerIoData.ListenSocket := ListenSocket;
  if (not AcceptEx(ListenSocket, ClientSocket, @PerIoData.Buffer.AcceptExBuffer, 0,
    SizeOf(TAddrBuffer), SizeOf(TAddrBuffer), Bytes, POverlapped(PerIoData))) then
  begin
    LastErr := WSAGetLastError;
    if (LastErr <> WSA_IO_PENDING) then
    begin
      AppendLog('%s.PostNewAcceptEx.AcceptEx(ListenSocket=%d, ClientSocket=%d), ERROR %d=%s', [ClassName, ListenSocket, ClientSocket, LastErr, SysErrorMessage(LastErr)], ltWarning);
      TrackSocketStatus(ClientSocket);
      FreeIoData(PerIoData);
      Connection.Disconnect;
      Exit;
    end;
  end;

  Result := True;
end;

function TIocpTcpSocket.AllocConnection(Socket: TSocket; Source: TConnectionSource): TIocpSocketConnection;
begin
  Result := TIocpSocketConnection(FConnectionPool.GetObject);

  Result.FSocket := Socket;
  Result.FConnectionSource := Source;
end;

function TIocpTcpSocket.AssociateSocketWithCompletionPort(Socket: TSocket;
  Connection: TIocpSocketConnection): Boolean;
var
  LastErr: DWORD;
begin
  Result := (Iocp.ApiFix.CreateIoCompletionPort(Socket, FIocpHandle, ULONG_PTR(Connection), 0) <> 0);
  if not Result then
  begin
    LastErr := GetLastError;
    AppendLog(Format('CreateIoCompletionPort(IocpHandle=%d, Socket=%d), ERROR %d=%s', [FIocpHandle, Socket, LastErr, SysErrorMessage(LastErr)]), ltWarning);
    TrackSocketStatus(Socket);
  end;
end;

function TIocpTcpSocket.AllocIoData(Socket: TSocket;
  Operation: TIocpOperationType): PIocpPerIoData;
begin
  Result := FPerIoDataPool.GetMemory(True);
  Result.ClientSocket := Socket;
  Result.Operation := Operation;
end;

procedure TIocpTcpSocket.DisconnectAll;
var
  Client: TIocpSocketConnection;
begin
  try
    FConnectionListLocker.Enter;

    // X.Values.ToArray�������б���һ������Ϊ���ӶϿ����
    // �Զ��Ӷ�Ӧ�Ĺ���/�����б���ɾ���������ɵ��������쳣����
    for Client in FConnectionList.Values.ToArray do
    begin
      Client._CloseSocket;
      Client.Release;
    end;

    for Client in FIdleConnectionList.Values.ToArray do
    begin
      Client._CloseSocket;
      Client.Release;
    end;
  finally
    FConnectionListLocker.Leave;
  end;
end;

function TIocpTcpSocket.AsyncConnect(const RemoteAddr: string; RemotePort: Word; Tag: Pointer): TSocket;
var
  InAddrInfo: TAddrInfoW;
  POutAddrInfo: PAddrInfoW;
  BindAddrIPv4: TSockAddrIn;
  BindAddrIPv6: TSockAddrIn6;
  PBindAddr: PSOCKADDR;
  BindAddrSize: Integer;
  ClientSocket: TSocket;
  Connection: TIocpSocketConnection;
  PerIoData: PIocpPerIoData;
  LastErr: Integer;
begin
  Result := INVALID_SOCKET;
  if IsShutdown then Exit;

  // �����������������
  if (FMaxClients > 0) and (FConnectionList.Count >= FMaxClients) then Exit;

  {
    64λ������gethostbyname���ص����ݽṹ��h_addr_listָ����Ч(ò�Ƹ�4�ֽں͵�4�ֽ�˳��ߵ���)
    ��getaddrinfo���ص����ݲ���������,���ҿ��Լ��IPv4��IPv6,ֻ��Ҫ�򵥵��޸ľ����ó���ͬʱ֧��
    IPv4��IPv6��
  }
  FillChar(InAddrInfo, SizeOf(TAddrInfoW), 0);
  InAddrInfo.ai_family := AF_UNSPEC;
  InAddrInfo.ai_socktype := SOCK_STREAM;
  InAddrInfo.ai_protocol := IPPROTO_TCP;
  POutAddrInfo := nil;
  if (getaddrinfo(PWideChar(RemoteAddr), PWideChar(IntToStr(RemotePort)), @InAddrInfo, @POutAddrInfo) <> 0) then
  begin
    LastErr := WSAGetLastError;
    AppendLog('%s.AsyncConnect.getaddrinfo, ERROR %d=%s', [ClassName, LastErr, SysErrorMessage(LastErr)], ltWarning);
    Exit;
  end;

  try
    ClientSocket := WSASocket(POutAddrInfo.ai_family, POutAddrInfo.ai_socktype,
      POutAddrInfo.ai_protocol, nil, 0, WSA_FLAG_OVERLAPPED);
    if (ClientSocket = INVALID_SOCKET) then Exit;

    if (POutAddrInfo.ai_family = AF_INET6) then
    begin
      BindAddrSize := SizeOf(BindAddrIPv6);
      ZeroMemory(@BindAddrIPv6, SizeOf(BindAddrIPv6));
      BindAddrIPv6.sin6_family := AF_INET6;
      BindAddrIPv6.sin6_addr := in6addr_any;
      BindAddrIPv6.sin6_port := 0;
      PBindAddr := @BindAddrIPv6;
    end else
    begin
      BindAddrSize := SizeOf(BindAddrIPv4);
      ZeroMemory(@BindAddrIPv4, SizeOf(BindAddrIPv4));
      BindAddrIPv4.sin_family := AF_INET;
      BindAddrIPv4.sin_addr.S_addr := INADDR_ANY;
      BindAddrIPv4.sin_port := 0;
      PBindAddr := @BindAddrIPv4;
    end;
    if (bind(ClientSocket, PBindAddr, BindAddrSize) = SOCKET_ERROR) then
    begin
      LastErr := WSAGetLastError;
      Iocp.Winsock2.closesocket(ClientSocket);
      AppendLog('%s.AsyncConnect.bind(Socket=%d), ERROR %d=%s', [ClassName, ClientSocket, LastErr, SysErrorMessage(LastErr)], ltWarning);
      Exit;
    end;

    // �����µ����Ӷ��󲢰󶨵�IOCP
    Connection := AllocConnection(ClientSocket, csConnect);
    Connection.Tag := Tag; // thanks Hezihang2012
    if not AssociateSocketWithCompletionPort(ClientSocket, Connection) then
    begin
      Iocp.Winsock2.closesocket(ClientSocket);
      FConnectionPool.FreeObject(Connection);
      Exit;
    end;

    if (Connection.AddRef = 1) then Exit;

    Connection.FIsIPv6 := (POutAddrInfo.ai_family = AF_INET6);
    ExtractAddrInfo(POutAddrInfo.ai_addr, POutAddrInfo.ai_addrlen, Connection.FRemoteIP, Connection.FRemotePort);

    // �����ӷŵ����������б���
    // ��ShutdownWorks�в��������ͷ�Socket��Դ����������Socket���й¶
    try
      FConnectionListLocker.Enter;
      FIdleConnectionList[ClientSocket] := Connection;
    finally
      FConnectionListLocker.Leave;
    end;

    PerIoData := AllocIoData(ClientSocket, iotConnect);
    if not ConnectEx(ClientSocket, POutAddrInfo.ai_addr, POutAddrInfo.ai_addrlen, nil, 0, PCardinal(0)^, PWSAOverlapped(PerIoData)) and
      (WSAGetLastError <> WSA_IO_PENDING) then
    begin
      LastErr := WSAGetLastError;
      AppendLog('%s.AsyncConnect.ConnectEx(Socket=%d), ERROR %d=%s', [ClassName, ClientSocket, LastErr, SysErrorMessage(LastErr)], ltWarning);
      FreeIoData(PerIoData);
      Connection.Release;
      Connection.Disconnect;
      Exit;
    end;
  finally
    freeaddrinfo(POutAddrInfo);
  end;
  Result := ClientSocket;
end;

function TIocpTcpSocket.Connect(const RemoteAddr: string;
  RemotePort: Word; Tag: Pointer; ConnectTimeout: DWORD): TIocpSocketConnection;
var
  Socket: TSocket;
  DummyHandle: THandle;
  t: DWORD;
begin
  Result := nil;
  Socket := AsyncConnect(RemoteAddr, RemotePort, Tag);
  if (Socket = INVALID_SOCKET) then Exit;

  if (ConnectTimeout <= 0) or (ConnectTimeout > 10000) then
    ConnectTimeout := 10000;

  t := GetTickCount;
  DummyHandle := INVALID_HANDLE_VALUE;
  while True do
  begin
    FConnectionListLocker.Enter;
    try
      Result := FConnectionList[Socket];
      if (Result <> nil) then Exit;
    finally
      FConnectionListLocker.Leave;
    end;

    if (MsgWaitForMultipleObjects(0, DummyHandle, False, 100, QS_ALLINPUT) = WAIT_OBJECT_0) then
      MessagePump;
    if (CalcTickDiff(t, GetTickCount) >= ConnectTimeout) then Exit;
  end;
end;

procedure TIocpTcpSocket.ExtractAddrInfo(const Addr: PSockAddr; AddrLen: Integer; out IP: string; out Port: Word);
var
  ServInfo: string;
begin
  SetLength(IP, NI_MAXHOST);
  SetLength(ServInfo, NI_MAXSERV);
  getnameinfo(Addr, AddrLen, PWideChar(IP), NI_MAXHOST, PWideChar(ServInfo), NI_MAXSERV, NI_NUMERICHOST or NI_NUMERICSERV);
  SetLength(IP, StrLen(PWideChar(IP)));
  SetLength(ServInfo, StrLen(PWideChar(ServInfo)));
  Port := StrToInt(ServInfo);
end;

procedure TIocpTcpSocket.FreeConnection(Connection: TIocpSocketConnection);
begin
  try
    FConnectionListLocker.Enter;
    if not FConnectionList.Delete(Connection.FSocket) then
      FIdleConnectionList.Delete(Connection.FSocket);
    FConnectionPool.FreeObject(Connection);
  finally
    FConnectionListLocker.Leave;
  end;
end;

procedure TIocpTcpSocket.FreeIoData(PerIoData: PIocpPerIoData);
begin
  FPerIoDataPool.FreeMemory(Pointer(PerIoData));
end;

function TIocpTcpSocket.GetConnectionClass: TIocpSocketConnectionClass;
begin
  Result := TIocpSocketConnectionClass(FConnectionPool.ObjectClass);
end;

function TIocpTcpSocket.GetConnectionFreeMemory: Integer;
begin
  Result := FConnectionPool.FreeObjectsSize;
end;

function TIocpTcpSocket.GetConnectionUsedMemory: Integer;
begin
  Result := FConnectionPool.UsedObjectsSize;
end;

function TIocpTcpSocket.GetIoCacheFreeMemory: Integer;
begin
  Result := FIoCachePool.FreeBlocksSize + FFileCachePool.FreeBlocksSize;
end;

function TIocpTcpSocket.GetIoCacheUsedMemory: Integer;
begin
  Result := FIoCachePool.UsedBlocksSize + FFileCachePool.UsedBlocksSize;
end;

function TIocpTcpSocket.GetPerIoFreeMemory: Integer;
begin
  Result := FPerIoDataPool.FreeBlocksSize;
end;

function TIocpTcpSocket.GetPerIoUsedMemory: Integer;
begin
  Result := FPerIoDataPool.UsedBlocksSize;
end;

function TIocpTcpSocket.IsShutdown: Boolean;
begin
  Result := (TInterlocked.Exchange(FShutdown, FShutdown) = 1);
end;

function TIocpTcpSocket.Listen(const Host: string; Port: Word; InitAcceptNum: Integer): Word;
const
  IPV6_V6ONLY = 27;
var
  PHost: PWideChar;
  ListenSocket: TSocket;
  InAddrInfo: TAddrInfoW;
  POutAddrInfo, Ptr: PAddrInfoW;
  Len: Integer;
  ListenCount: Integer;
  LastErr: Integer;
begin
  Result := 0;
  if IsShutdown or not Assigned(FAcceptThread) then Exit;

  try
    // ���������һ����Ч��ַ������õ�ַ
    // ����������б��ص�ַ
    if (Host = '') then
      PHost := nil
    else
      PHost := PWideChar(Host);

    FillChar(InAddrInfo, SizeOf(TAddrInfoW), 0);
    InAddrInfo.ai_flags := AI_PASSIVE;
    InAddrInfo.ai_family := AF_UNSPEC;
    InAddrInfo.ai_socktype := SOCK_STREAM;
    InAddrInfo.ai_protocol := IPPROTO_TCP;
    if (getaddrinfo(PHost, PWideChar(IntToStr(Port)), @InAddrInfo, @POutAddrInfo) <> 0) then
    begin
      LastErr := WSAGetLastError;
      AppendLog('%s.Listen.getaddrinfo, ERROR %d=%s', [ClassName, LastErr, SysErrorMessage(LastErr)], ltWarning);
      Exit;
    end;

    try
      {$region '�����������Ƿ��Ѵ�����'}
      Ptr := POutAddrInfo;
      ListenCount := FAcceptThread.ListenCount;
      while (Ptr <> nil) do
      begin
        Inc(ListenCount);
        Ptr := Ptr.ai_next;
      end;
      if (ListenCount > FAcceptThread.MAX_LISTEN_SOCKETS) then Exit;
      {$endregion}

      Ptr := POutAddrInfo;
      while (Ptr <> nil) do
      begin
        ListenSocket := WSASocket(Ptr.ai_family, Ptr.ai_socktype, Ptr.ai_protocol, nil, 0, WSA_FLAG_OVERLAPPED);
        if (ListenSocket = INVALID_SOCKET) then Exit;

//        no := 0;
//        setsockopt(ListenSocket, IPPROTO_IPV6, IPV6_V6ONLY, PAnsiChar(@no), sizeof(no));

        if (bind(ListenSocket, Ptr.ai_addr, Ptr.ai_addrlen) = SOCKET_ERROR) then
        begin
          LastErr := WSAGetLastError;
          Iocp.Winsock2.closesocket(ListenSocket);
          AppendLog('%s.Listen.bind(Port=%d, Socket=%d), ERROR %d=%s', [ClassName, Port, ListenSocket, LastErr, SysErrorMessage(LastErr)], ltWarning);
          Exit;
        end;

        if (Iocp.Winsock2.listen(ListenSocket, SOMAXCONN) = SOCKET_ERROR) then
        begin
          LastErr := WSAGetLastError;
          Iocp.Winsock2.closesocket(ListenSocket);
          AppendLog('%s.Listen.listen(Port=%d, Socket=%d), ERROR %d=%s', [ClassName, Port, ListenSocket, LastErr, SysErrorMessage(LastErr)], ltWarning);
          Exit;
        end;

        if not AssociateSocketWithCompletionPort(ListenSocket, nil) then
        begin
          Iocp.Winsock2.closesocket(ListenSocket);
          AppendLog('%s.Listen.AssociateSocketWithCompletionPort(Port=%d, Socket=%d) failed', [ClassName, Port, ListenSocket], ltWarning);
          Exit;
        end;

        if not FAcceptThread.NewListen(ListenSocket, Ptr.ai_family, InitAcceptNum) then
        begin
          Iocp.Winsock2.closesocket(ListenSocket);
          Exit;
        end;

        // ���Port����0�����������˿ڣ�����ȡ��ʵ�ʷ���Ķ˿ں�
        if (Port = 0) then
        begin
          Len := Ptr.ai_addrlen;
          if (getsockname(ListenSocket, Ptr.ai_addr, Len) = -1) then
          begin
            LastErr := WSAGetLastError;
            AppendLog('%s.Listen.getsockname(Port=%d, Socket=%d), ERROR %d=%s', [ClassName, Port, ListenSocket, LastErr, SysErrorMessage(LastErr)], ltWarning);
            Exit;
          end;
          Port := ntohs(Ptr.ai_addr.sin_port);
        end;

        // ����˿ڴ���0�������е�ַͳһ���׸����䵽�Ķ˿�
        if (Ptr.ai_next <> niL) then
          Ptr.ai_next.ai_addr.sin_port := Ptr.ai_addr.sin_port;

        Ptr := Ptr.ai_next;
      end;
    finally
      freeaddrinfo(POutAddrInfo);
    end;

    Result := Port;
  except
    on e: Exception do
      AppendLog('%s.Listen ERROR %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
end;

function TIocpTcpSocket.Listen(Port: Word; InitAcceptNum: Integer): Word;
begin
  Result := Listen('', Port, InitAcceptNum);
end;

function TIocpTcpSocket.LockConnectionList: TIocpSocketConnectionDictionary;
begin
  Result := FConnectionList;
  FConnectionListLocker.Enter;
end;

procedure TIocpTcpSocket.UnlockConnectionList;
begin
  FConnectionListLocker.Leave;
end;

procedure TIocpTcpSocket.MessagePump;
begin
  while ProcessMessage do;
end;

function TIocpTcpSocket.ProcessMessage: Boolean;
var
  Msg: TMsg;
begin
  Result := False;
  if PeekMessage(Msg, 0, 0, 0, PM_REMOVE) then
  begin
    Result := True;
    if (Msg.Message = WM_QUIT) then
    begin
    end
    else
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
  end;
end;

procedure TIocpTcpSocket.ProcessRequest(Connection: TIocpSocketConnection;
  PerIoData: PIocpPerIoData; IoThread: TIocpIoThread);
begin
  try
    try
      case PerIoData.Operation of
        iotAccept:     RequestAcceptComplete(PerIoData);
        iotConnect:    RequestConnectComplete(Connection);
        iotDisconnect: RequestDisconnectComplete(Connection);
        iotReadZero:   RequestReadZeroComplete(Connection, PerIoData);
        iotRead:       RequestReadComplete(Connection, PerIoData);
        iotWrite:      RequestWriteComplete(Connection, PerIoData);
      end;
    finally
      FreeIoData(PerIoData);
    end;
  except
    on e: Exception do
      AppendLog('%s.ProcessRequest ERROR %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
end;

procedure TIocpTcpSocket.RequestAcceptComplete(PerIoData: PIocpPerIoData);
var
  Connection: TIocpSocketConnection;
  LocalAddrLen, RemoteAddrLen: Integer;
  PLocalAddr, PRemoteAddr: PSockAddr;
begin
  if IsShutdown then Exit;
  
  try
    // �����ӷŵ����������б���
    try
      FConnectionListLocker.Enter;
      Connection := FIdleConnectionList[PerIoData.ClientSocket];
      // ���֮ǰ�����Ӵ����ڿ��������б��������Ƶ����������б���
      if (Connection <> nil) then
      begin
        FConnectionList[PerIoData.ClientSocket] := Connection;
        FIdleConnectionList.Delete(Connection.FSocket);
      end else
      //** ��������Զ����ִ�е�������
      begin
        Connection := FConnectionList[PerIoData.ClientSocket];
        if (Connection = nil) then
        begin
          Connection := AllocConnection(PerIoData.ClientSocket, csAccept);
          FConnectionList[PerIoData.ClientSocket] := Connection;
        end;
      end;
    finally
      FConnectionListLocker.Leave;
    end;

    // ��Socket���IOCP
    if not AssociateSocketWithCompletionPort(PerIoData.ClientSocket, Connection) then
    begin
      AppendLog(
        '%s.RequestAcceptComplete.AssociateSocketWithCompletionPort failed, Socket=%d',
        [ClassName, PerIoData.ClientSocket],
        ltWarning);
      Connection.Release;
      Exit;
    end;

    Connection.UpdateTick;

    // ����SO_UPDATE_ACCEPT_CONTEXT,���һ������optlenʵ����Ҫ�趨ΪSizeOf(PAnsiChar)
    // ��һ����MSDN�������ж��Ǵ�ģ���Ϊ����ʵ�ʲ��Է�����64λ���������ﴫ��SizeOf(PerIoData.ListenSocket)
    // �Ļ��ᱨ��10014,ϵͳ��⵽��һ�������г���ʹ��ָ�����ʱ����Чָ���ַ��
    // Ҳ����˵�����optlenʵ����Ӧ�ô��ݵ���һ��ָ��ĳ���(Ӧ�ø��ڴ�����й�ϵ)
    if (setsockopt(PerIoData.ClientSocket, SOL_SOCKET, SO_UPDATE_ACCEPT_CONTEXT,
      PAnsiChar(@PerIoData.ListenSocket), SizeOf(PAnsiChar)) = SOCKET_ERROR) then
    begin
      AppendLog(
        '%s.RequestAcceptComplete.setsockopt.SO_UPDATE_ACCEPT_CONTEXT, Socket=%d, ERROR %d=%s',
        [ClassName, PerIoData.ClientSocket, WSAGetLastError, SysErrorMessage(WSAGetLastError)],
        ltWarning);
      Connection.Disconnect;
      Exit;
    end;

    // ��ȡ���ӵ�ַ��Ϣ
    GetAcceptExSockaddrs(@PerIoData.Buffer.AcceptExBuffer[0], 0, SizeOf(TAddrBuffer),
      SizeOf(TAddrBuffer), PLocalAddr, LocalAddrLen,
      PRemoteAddr, RemoteAddrLen);

    if not Connection.InitSocket then
    begin
      Connection.Disconnect;
      Exit;
    end;

    // ������ַ��Ϣ
    ExtractAddrInfo(PRemoteAddr, RemoteAddrLen, Connection.FRemoteIP, Connection.FRemotePort);

    // ��������������������Ͽ�
    if (FMaxClients > 0) and (FConnectionList.Count > FMaxClients) then
    begin
      Connection.Disconnect;
      Exit;
    end;

    Connection.TriggerConnected;

    // ���ӽ���֮��PostZero��ȡ����
    if not Connection.PostReadZero then Exit;
  except
    on e: Exception do
      AppendLog('%s.RequestAcceptComplete ERROR %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
end;

procedure TIocpTcpSocket.RequestConnectComplete(Connection: TIocpSocketConnection);
begin
  if IsShutdown then Exit;

  try
    try
      try
        FConnectionListLocker.Enter;
        FIdleConnectionList.Delete(Connection.FSocket);
        FConnectionList[Connection.FSocket] := Connection;
      finally
        FConnectionListLocker.Leave;
      end;

      if not Connection.InitSocket then
      begin
        Connection.Disconnect;
        Exit;
      end;

      Connection.UpdateTick;
      Connection.TriggerConnected;

      // ���ӽ���֮��PostZero��ȡ����
      if not Connection.PostReadZero then Exit;
    finally
      Connection.Release; // ��Ӧ AsyncConnect �е� AddRef;
    end;
  except
    on e: Exception do
      AppendLog('%s.RequestConnectComplete ERROR %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
end;

procedure TIocpTcpSocket.RequestDisconnectComplete(
  Connection: TIocpSocketConnection);
begin
  try
    Connection.Release;
  finally
    Connection.Release; // ��Ӧ Disconnect �е� AddRef;
  end;
end;

procedure TIocpTcpSocket.RequestReadZeroComplete(
  Connection: TIocpSocketConnection; PerIoData: PIocpPerIoData);
begin
  try
    try
      if (Connection.IsClosed) then Exit;

      Connection.UpdateTick;

      // ��ʽ��ʼ��������
      Connection.PostRead;
    finally
      Connection.Release; // ��ӦPostReadZero�е�AddRef
    end;
  except
    on e: Exception do
      AppendLog('%s.RequestReadZeroComplete ERROR %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
end;

procedure TIocpTcpSocket.RequestReadComplete(Connection: TIocpSocketConnection;
  PerIoData: PIocpPerIoData);
begin
  try
    try
      Connection.DecPendingRecv;

      if (Connection.IsClosed) then Exit;

      if (PerIoData.BytesTransfered = 0) or (PerIoData.Buffer.DataBuf.buf = nil) then
      begin
        Connection.Disconnect;
        Exit;
      end;

      Connection.UpdateTick;

      // PerIoData.Buffer.DataBuf �����ѽ��յ������ݣ�PerIoData.BytesTransfered ��ʵ�ʽ��յ����ֽ���
      TInterlocked.Add(FRecvBytes, PerIoData.BytesTransfered);
      PerIoData.Buffer.DataBuf.Len := PerIoData.BytesTransfered;

      try
        TInterlocked.Increment(FPendingRequest);
        Connection.TriggerRecvData(PerIoData.Buffer.DataBuf.buf, PerIoData.Buffer.DataBuf.len);
      finally
        TInterlocked.Decrement(FPendingRequest);
      end;

      // �������տͻ�������
      Connection.PostReadZero;
    finally
      Connection.Release; // ��ӦPostRead�е�AddRef
    end;
  except
    on e: Exception do
      AppendLog('%s.RequestReadComplete ERROR %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
end;

procedure TIocpTcpSocket.RequestWriteComplete(Connection: TIocpSocketConnection;
  PerIoData: PIocpPerIoData);
begin
  try
    try
      Connection.DecPendingSend;

      if (Connection.IsClosed) then Exit;

      if (PerIoData.BytesTransfered = 0) or (PerIoData.Buffer.DataBuf.buf = nil) then
      begin
        Connection.Disconnect;
        Exit;
      end;

      Connection.UpdateTick;

      TInterlocked.Add(FSentBytes, PerIoData.BytesTransfered);
      PerIoData.Buffer.DataBuf.Len := PerIoData.BytesTransfered;
      Connection.TriggerSentData(PerIoData.Buffer.DataBuf.Buf, PerIoData.Buffer.DataBuf.Len);
    finally
      FIoCachePool.FreeMemory(PerIoData.Buffer.DataBuf.Buf); // ��ӦPostWrite�з���ķ����ڴ��
      Connection.Release; // ��ӦPostWrite�е�AddRef
    end;
  except
    on e: Exception do
      AppendLog('%s.RequestWriteComplete ERROR %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
end;

procedure TIocpTcpSocket.SetConnectionClass(
  const Value: TIocpSocketConnectionClass);
begin
  FConnectionPool.ObjectClass := Value;
end;

procedure TIocpTcpSocket.StartupWorkers;
var
  NumberOfThreads, i: Integer;
begin
  if (FIocpHandle <> 0) then Exit;

  FPendingRequest := 0;

  // ����IO�߳���
  if (FIoThreadsNumber <= 0) then
    NumberOfThreads := CPUCount * 2
  else
    NumberOfThreads := Min(FIoThreadsNumber, 64);

  // ������ɶ˿�
  // NumberOfConcurrentThreads = 0 ��ʾÿ��CPU����һ�������߳�
  FIocpHandle := Iocp.ApiFix.CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 0);
  if (FIocpHandle = INVALID_HANDLE_VALUE) then
    raise Exception.CreateFmt('%s.StartupWorkers����IOCP����ʧ��', [ClassName]);

  // ����IO�߳�
  SetLength(FIoThreads, NumberOfThreads);
  SetLength(FIoThreadHandles, NumberOfThreads);
  for i := 0 to NumberOfThreads - 1 do
  begin
    FIoThreads[i] := TIocpIoThread.Create(Self);
    FIoThreadHandles[i] := FIoThreads[i].Handle;
  end;

  // ���������߳�
  FAcceptThread := TIocpAcceptThread.Create(Self);

  FSentBytes := 0;
  FRecvBytes := 0;
  TInterlocked.Exchange(FShutdown, 0);
end;

procedure TIocpTcpSocket.ShutdownWorkers;
var
  i: Integer;
  LTick, LTimeout: LongWord;
begin
  TInterlocked.Exchange(FShutdown, 1);
  if (FIocpHandle = 0) then Exit;

  // �رռ����߳�
  if Assigned(FAcceptThread) then
  begin
    FAcceptThread.Quit;
    FAcceptThread.WaitFor;
    FreeAndNil(FAcceptThread);
  end;

  // �Ͽ���������
  DisconnectAll;

  {$IFDEF __TIME_OUT_TIMER__}
  if (FTimeout > 0) and (FTimeout < 5000) then
    LTimeout := FTimeout
  else
  {$ENDIF}
    LTimeout := 5000;

  // ����������Sleep���Ա�֤���жϿ����ӵ�����Ⱥ����˳��̵߳������Ƚ���IOCP����
  // ������ܻ�������ӻ�ûȫ���ͷţ��߳̾ͱ���ֹ�ˣ������Դй©
  LTick := GetTickCount;
  while ((FConnectionList.Count > 0) or (FIdleConnectionList.Count > 0)) do
  begin
    SleepEx(10, True);
    if (CalcTickDiff(LTick, GetTickCount) > LTimeout) then Break;
  end;

  // �ر�IO�߳�
  for i := Low(FIoThreads) to High(FIoThreads) do
  begin
    Iocp.ApiFix.PostQueuedCompletionStatus(FIocpHandle, 0, 0, POverlapped(SHUTDOWN_FLAG));
    SleepEx(10, True);
  end;

  // �ȴ�IO�߳̽���
  WaitForMultipleObjects(Length(FIoThreadHandles), Pointer(FIoThreadHandles), True, LTimeout);

  // �ͷ��̶߳���
  for i := Low(FIoThreads) to High(FIoThreads) do
    FIoThreads[I].Free;
  SetLength(FIoThreads, 0);
  SetLength(FIoThreadHandles, 0);

  // �ر���ɶ˿�
  CloseHandle(FIocpHandle);
  FIocpHandle := 0;

  FConnectionList.Clear;
  FIdleConnectionList.Clear;
  FConnectionPool.Clear;
  FPerIoDataPool.Clear;
  FIoCachePool.Clear;
  FFileCachePool.Clear;

//  AppendLog('%s.shutdown compelte, ConnCount=%d, IdleConnCount=%d',
//    [ClassName, FConnectionList.Count, FIdleConnectionList.Count]);
end;

procedure TIocpTcpSocket.StopListen(ListenSocket: TSocket);
begin
  if Assigned(FAcceptThread) then
    FAcceptThread.StopListen(ListenSocket);
end;

procedure TIocpTcpSocket.TrackSocketStatus(Socket: TSocket);
var
  OptLen, OptVal: Integer;
  LastErr: DWORD;
begin
  OptLen := SizeOf(OptVal);
  if (getsockopt(Socket, SOL_SOCKET, SO_ERROR, PAnsiChar(@OptVal), OptLen) = SOCKET_ERROR) then
  begin
    LastErr := GetLastError;
    AppendLog(Format('getsockopt.SO_ERROR failed, IocpHandle=%d, Socket=%d, ERROR %d=%s', [FIocpHandle, Socket, LastErr, SysErrorMessage(LastErr)]), ltWarning);
  end else
    AppendLog(Format('getsockopt.SO_ERROR success, IocpHandle=%d, Socket=%d, OptVal=%d', [FIocpHandle, Socket, OptVal]), ltWarning);
end;

procedure TIocpTcpSocket.TriggerClientConnected(
  Client: TIocpSocketConnection);
begin
  if Assigned(OnClientConnected) then
    OnClientConnected(Self, Client);
end;

procedure TIocpTcpSocket.TriggerClientDisconnected(
  Client: TIocpSocketConnection);
begin
  if Assigned(OnClientDisconnected) then
    OnClientDisconnected(Self, Client);
end;

procedure TIocpTcpSocket.TriggerClientRecvData(
  Client: TIocpSocketConnection; Buf: Pointer; Len: Integer);
begin
  if Assigned(OnClientRecvData) then
    OnClientRecvData(Self, Client, Buf, Len)
end;

procedure TIocpTcpSocket.TriggerClientSentData(
  Client: TIocpSocketConnection; Buf: Pointer; Len: Integer);
begin
  if Assigned(OnClientSentData) then
    OnClientSentData(Self, Client, Buf, Len);
end;

initialization
//  Iocp.Winsock2.InitializeWinSock;
//  Iocp.Wship6.InitLibrary;
//  InitializeStubsEx;

finalization
//  Iocp.Winsock2.UninitializeWinSock;

end.

