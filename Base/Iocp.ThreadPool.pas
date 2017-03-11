unit Iocp.ThreadPool;

{*
  ����IOCPʵ�ֵ��̳߳أ�Ч��Զ������ͨ�̳߳�
  ����Synopse�е��̳߳ش���ı�
 *}

interface

uses
  Windows, Classes, SysUtils, Math, System.Generics.Collections, System.SyncObjs,
  Iocp.ApiFix;

const
  SHUTDOWN_FLAG = ULONG_PTR(-1);

type
  TIocpThreadPool = class;
  TProcessorThread = class;

  // �̳߳�������
  TIocpThreadRequest = class abstract(TObject)
  private
    FPool: TIocpThreadPool;
    FThread: TProcessorThread;
  protected
    // �̳߳ع�������
    // �̳����������д�Լ����̴߳���
    procedure Execute; virtual; abstract;
  public
    property Pool: TIocpThreadPool read FPool;
    property Thread: TProcessorThread read FThread;
  end;

  // �����߳�
  TProcessorThread = class(TThread)
  private
    FPool: TIocpThreadPool;
    FTag: Pointer;
  protected
    procedure Execute; override;
  public
    constructor Create(Pool: TIocpThreadPool); reintroduce; virtual;

    property Pool: TIocpThreadPool read FPool;
    property Tag: Pointer read FTag write FTag;
  end;

  TProcessorThreadArray = array of TProcessorThread;

  // �̳߳�
  TIocpThreadPool = class
  protected
    FIocpHandle: THandle;
    FNumberOfThreads: Integer;
    FThreads: TProcessorThreadArray;
    FThreadHandles: array of THandle;
    FRequests: TList<TIocpThreadRequest>;
    FReqLocker: TCriticalSection;
    FPendingRequest: Integer;
    FShutdowned: Boolean;

    // �߳������¼�
    procedure DoThreadStart(Thread: TProcessorThread); virtual;

    // �߳̽����¼�
    procedure DoThreadExit(Thread: TProcessorThread); virtual;
  public
    // NumberOfThreads=�߳��������<=0���Զ�����CPU��������������߳���
    constructor Create(NumberOfThreads: Integer = 0; Suspend: Boolean = False);
    destructor Destroy; override;

    function AddRequest(Request: TIocpThreadRequest): Boolean; virtual;
    procedure Startup;
    procedure Shutdown;

    property Threads: TProcessorThreadArray read FThreads;
    property PendingRequest: Integer read FPendingRequest;
    property Shutdowned: Boolean read FShutdowned;
  end;

implementation

{ TProcessorThread }

constructor TProcessorThread.Create(Pool: TIocpThreadPool);
begin
  inherited Create(True);

  FPool := Pool;

  FTag := nil;
  Suspended := False;
end;

procedure TProcessorThread.Execute;
var
  Bytes: DWORD;
  Request: TIocpThreadRequest;
  CompKey: ULONG_PTR;
begin
  FPool.DoThreadStart(Self);
  while not Terminated and Iocp.ApiFix.GetQueuedCompletionStatus(FPool.FIocpHandle, Bytes, CompKey, POverlapped(Request), INFINITE) do
  try
    // ������Ч�����󣬺���
    if (CompKey <> ULONG_PTR(FPool)) then Continue;

    // �յ��߳��˳���־������ѭ��
    if (ULONG_PTR(Request) = SHUTDOWN_FLAG) then Break;

    if (Request <> nil) then
    try
      FPool.FReqLocker.Enter;
      FPool.FRequests.Remove(Request);
      FPool.FReqLocker.Leave;

      Request.FPool := FPool;
      Request.FThread := Self;
      Request.Execute;
    finally
      InterlockedDecrement(FPool.FPendingRequest);
      Request.Free;
    end;
  except
  end;
  FPool.DoThreadExit(Self);
end;

{ TIocpThreadPool }

// NumberOfThreads �߳���������趨Ϊ0�����Զ�����CPU��������������߳���
constructor TIocpThreadPool.Create(NumberOfThreads: Integer; Suspend: Boolean);
begin
  FReqLocker := TCriticalSection.Create;
  FRequests := TList<TIocpThreadRequest>.Create;
  FNumberOfThreads := NumberOfThreads;
  FIocpHandle := 0;
  FShutdowned := True;

  if not Suspend then
    Startup;
end;

destructor TIocpThreadPool.Destroy;
begin
  Shutdown;
  FRequests.Free;
  FReqLocker.Free;
  inherited Destroy;
end;

procedure TIocpThreadPool.DoThreadStart(Thread: TProcessorThread);
begin
end;

procedure TIocpThreadPool.DoThreadExit(Thread: TProcessorThread);
begin
end;

function TIocpThreadPool.AddRequest(Request: TIocpThreadRequest): Boolean;
begin
  Result := False;
  if (FIocpHandle = 0) then Exit;

  FReqLocker.Enter;
  FRequests.Add(Request);
  FReqLocker.Leave;

  InterlockedIncrement(FPendingRequest);
  Result := Iocp.ApiFix.PostQueuedCompletionStatus(FIocpHandle, 0, ULONG_PTR(Self), POverlapped(Request));
  if not Result then
    InterlockedDecrement(FPendingRequest);
end;

procedure TIocpThreadPool.Startup;
var
  NumberOfThreads, i: Integer;
begin
  if (FIocpHandle <> 0) then Exit;

  if (FNumberOfThreads <= 0) then
    NumberOfThreads := CPUCount * 2
  else
    NumberOfThreads := Min(FNumberOfThreads, 64); // maximum count for WaitForMultipleObjects()

  // ������ɶ˿�
  // NumberOfConcurrentThreads = 0 ��ʾÿ��CPU����һ�������߳�
  FIocpHandle := Iocp.ApiFix.CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 0);
  if (FIocpHandle = INVALID_HANDLE_VALUE) then
    raise Exception.Create('IocpThreadPool����IOCP����ʧ��');

  // �������й����߳�
  Setlength(FThreads, NumberOfThreads);
  SetLength(FThreadHandles, NumberOfThreads);
  for i := 0 to NumberOfThreads - 1 do
  begin
    FThreads[i] := TProcessorThread.Create(Self);
    FThreadHandles[i] := FThreads[i].Handle;
  end;

  FShutdowned := False;
end;

procedure TIocpThreadPool.Shutdown;
var
  i: Integer;
begin
  if (FIocpHandle = 0) then Exit;

  FShutdowned := True;

  // �����й����̷߳����˳�����
  for i := 0 to High(FThreads) do
  begin
    Iocp.ApiFix.PostQueuedCompletionStatus(FIocpHandle, 0, ULONG_PTR(Self), POverLapped(SHUTDOWN_FLAG));
    SleepEx(10, True);
  end;

  // �ȴ������߳̽���
  WaitForMultipleObjects(Length(FThreadHandles), Pointer(FThreadHandles), True, INFINITE);

  // �ͷ��̶߳���
  for i := 0 to High(FThreads) do
    FThreads[I].Free;

  // �ر���ɶ˿ھ��
  CloseHandle(FIocpHandle);
  FIocpHandle := 0;

  SetLength(FThreads, 0);
  SetLength(FThreadHandles, 0);

  FReqLocker.Enter;
  try
    for i := 0 to FRequests.Count - 1 do
    begin
      FRequests[i].Free;
    end;
    FRequests.Clear;
  finally
    FReqLocker.Leave;
  end;
end;

end.
