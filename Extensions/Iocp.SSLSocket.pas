unit Iocp.SSLSocket;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, Iocp.TcpSocket, Iocp.OpenSSL;

type
  TIocpSSLConnection = class(TIocpSocketConnection)
  private
    FSsl: PSSL;
    FRecvBIO, FSendBIO: PBIO;
    FBufSize: Integer;
    FRecvSslBuffer, FSendSslBuffer: Pointer;
    FSslHandshaking: Boolean;
    FLocker: TCriticalSection;

    procedure Lock;
    procedure Unlock;

    procedure SSLHandleshaking;
  protected
    function PostWrite(const Buf: Pointer; Size: Integer): Boolean; override;

    procedure TriggerConnected; override;
    procedure TriggerRecvData(Buf: Pointer; Len: Integer); override;
    procedure TriggerSentData(Buf: Pointer; Len: Integer); override;
  public
    constructor Create(AOwner: TObject); override;
    destructor Destroy; override;
  end;

  TIocpSSLSocket = class(TIocpTcpSocket)
  private
    FSslCtx: PSSL_CTX;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure SetCert(CertPKey: Pointer; CertPKeySize: Integer); overload;
    procedure SetCert(Cert: Pointer; CertSize: Integer; PKey: Pointer; PKeySize: Integer); overload;
    procedure SetCert(const CertPKeyFile: string); overload;
    procedure SetCert(const CertFile, PKeyFile: string); overload;
  end;

implementation

uses
  System.IOUtils;

{ TIocpSSLConnection }

constructor TIocpSSLConnection.Create(AOwner: TObject);
begin
  inherited Create(AOwner);

  FLocker := TCriticalSection.Create;
  FBufSize := Owner.IoCachePool.BlockSize;
  FRecvSslBuffer := Owner.IoCachePool.GetMemory(False);
  FSendSslBuffer := Owner.IoCachePool.GetMemory(False);

  FSsl := SSL_new(TIocpSSLSocket(Owner).FSslCtx);
  FRecvBIO := BIO_new(BIO_s_mem());
  FSendBIO := BIO_new(BIO_s_mem());
  SSL_set_bio(FSsl, FRecvBIO, FSendBIO);
end;

destructor TIocpSSLConnection.Destroy;
begin
  SSL_shutdown(FSsl);
  SSL_free(FSsl);
  Owner.IoCachePool.FreeMemory(FRecvSslBuffer);
  Owner.IoCachePool.FreeMemory(FSendSslBuffer);
  FLocker.Free;

  inherited Destroy;
end;

procedure TIocpSSLConnection.Lock;
begin
  FLocker.Enter;
end;

procedure TIocpSSLConnection.Unlock;
begin
  FLocker.Leave;
end;

procedure TIocpSSLConnection.SSLHandleshaking;
var
  bytes, error: Integer;
begin
  // �Ƿ���Ҫ������������
  if (BIO_pending(FSendBIO) <> 0) then
  begin
    bytes := BIO_read(FSendBIO, FSendSslBuffer, FBufSize);
    if (bytes <= 0) then
    begin
      error := SSL_get_error(FSsl, bytes);
      if ssl_is_fatal_error(error) then
        Disconnect;
      Exit;
    end;
    inherited PostWrite(FSendSslBuffer, bytes);
  end;

  // �������
  if FSslHandshaking and SSL_is_init_finished(FSsl) then
  begin
    FSslHandshaking := False;
    inherited TriggerConnected;
  end;
end;

function TIocpSSLConnection.PostWrite(const Buf: Pointer;
  Size: Integer): Boolean;
var
  bytes, error: Integer;
begin
  Result := False;
  Lock;
  try
    // �����������ݼ���
    bytes := SSL_write(FSsl, Buf, Size);
    if (bytes <> Size) then
    begin
      error := SSL_get_error(FSsl, bytes);
      if ssl_is_fatal_error(error) then
      begin
        Disconnect;
        Exit;
      end;
    end;

    // �� BIO ��ȡ���ܺ�����ݷ���
    while (BIO_pending(FSendBIO) <> 0) do
    begin
      bytes := BIO_read(FSendBIO, FSendSslBuffer, FBufSize);
      if (bytes <= 0) then
      begin
        error := SSL_get_error(FSsl, bytes);
        if ssl_is_fatal_error(error) then
          Disconnect;
        Break;
      end;

      Result := inherited PostWrite(FSendSslBuffer, bytes);
      if not Result then Break;
    end;
  finally
    Unlock;
  end;
end;

procedure TIocpSSLConnection.TriggerConnected;
var
  bytes, error: Integer;
begin
  FSslHandshaking := True;
  Lock;
  try
    // ���ӽ�������� SSL_read ��ʼSSL����
    if (ConnectionSource = csAccept) then
    begin
      SSL_set_accept_state(FSsl);
      bytes := SSL_read(FSsl, FRecvSslBuffer, FBufSize);
    end else
    begin
      SSL_set_connect_state(FSsl);
      bytes := SSL_read(FSsl, FRecvSslBuffer, FBufSize);
    end;

    if (bytes <= 0) then
    begin
      error := SSL_get_error(FSsl, bytes);
      if ssl_is_fatal_error(error) then
      begin
        Disconnect;
        Exit;
      end;
    end;

    SSLHandleshaking;
  finally
    Unlock;
  end;
end;

procedure TIocpSSLConnection.TriggerRecvData(Buf: Pointer; Len: Integer);
var
  error, bytes: Integer;
begin
  Lock;
  try
    // ���յ��ļ�������д�� BIO
    // �����յ������ݼ��п�������������Ҳ�п�����ʵ������
    while True do
    begin
      bytes := BIO_write(FRecvBIO, Buf, Len);
      if (bytes > 0) then Break;

      if not BIO_should_retry(FRecvBIO) then
      begin
        Disconnect;
        Exit;
      end;
    end;

    // ��ȡ���ܺ������
    // �����ʵ�������ܶ�ȡ�ɹ���
    // �������ݱ�Ȼ��ȡʧ�ܣ��Ӷ�����������һ������
    while True do
    begin
      bytes := SSL_read(FSsl, FRecvSslBuffer, FBufSize);
      if (bytes > 0) then
        // �յ�ʵ������
        inherited TriggerRecvData(FRecvSslBuffer, bytes)
      else
      begin
        error := SSL_get_error(FSsl, bytes);
        if ssl_is_fatal_error(error) then
        begin
          Disconnect;
          Exit;
        end;

        Break;
      end;
    end;

    SSLHandleshaking;
  finally
    Unlock;
  end;
end;

procedure TIocpSSLConnection.TriggerSentData(Buf: Pointer; Len: Integer);
begin
  if not FSslHandshaking then
    inherited TriggerSentData(Buf, Len);
end;

{ TIocpSSLSocket }

constructor TIocpSSLSocket.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ConnectionClass := TIocpSSLConnection;

  TSSLTools.LoadSSL;
  FSslCtx := TSSLTools.NewCTX;
end;

destructor TIocpSSLSocket.Destroy;
begin
  inherited Destroy;

  TSSLTools.FreeCTX(FSslCtx);
  TSSLTools.UnloadSSL;
end;

procedure TIocpSSLSocket.SetCert(CertPKey: Pointer; CertPKeySize: Integer);
begin
  TSSLTools.SetCert(FSslCtx, CertPKey, CertPKeySize);
end;

procedure TIocpSSLSocket.SetCert(Cert: Pointer; CertSize: Integer;
  PKey: Pointer; PKeySize: Integer);
begin
  TSSLTools.SetCert(FSslCtx, Cert, CertSize, PKey, PKeySize);
end;

procedure TIocpSSLSocket.SetCert(const CertPKeyFile: string);
begin
  TSSLTools.SetCert(FSslCtx, CertPKeyFile);
end;

procedure TIocpSSLSocket.SetCert(const CertFile, PKeyFile: string);
begin
  TSSLTools.SetCert(FSslCtx, CertFile, PKeyFile);
end;

end.
