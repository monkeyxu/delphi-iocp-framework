unit Iocp.MemoryPool;

{* ʵ�ʲ��Է���,32λ��С���ڴ�(<4K)�ķ���,Delphi�Դ���GetMem��HeapAllocЧ�ʸߺܶ�
 * ��ʹGetMem + ZeroMemoryҲ��HeapAlloc��$08(��0�ڴ�)��־��
 * ����64λ�»��ߴ���ڴ�(>4K)�ķ���HeapAlloc/HealFree�����Ը�
 *}
{$define __HEAP_ALLOC__}

interface

uses
  Windows, Types, Classes, SysUtils, SyncObjs, Iocp.Logger;

type
  TIocpMemoryPool = class
  private const
    {$ifdef __HEAP_ALLOC__}
    HEAP_ALLOC_FLAG: array [Boolean] of DWORD = ($00, $08);
    {$endif}
  private
    {$ifdef __HEAP_ALLOC__}
    FHeapHandle: THandle;
    {$endif}
    FRefCount: Integer;
    FBlockSize, FMaxFreeBlocks: Integer;
    FFreeMemoryBlockList: TList; // ����ʵ�ʲ��ԣ�ʹ��Classes.TList��Collections.TList<>Ч�ʸ���
    FUsedMemoryBlockList: TList;
    FLocker: TCriticalSection;

    function GetFreeBlocks: Integer;
    function GetFreeBlocksSize: Integer;
    function GetUsedBlocks: Integer;
    function GetUsedBlocksSize: Integer;
    procedure SetMaxFreeBlocks(MaxFreeBlocks: Integer);
  protected
    function RealAlloc(Size: Integer; Zero: Boolean): Pointer; inline;
    procedure RealFree(P: Pointer); inline;
  public
    constructor Create(BlockSize, MaxFreeBlocks: Integer); virtual;
    destructor Destroy; override;

    procedure Lock; inline;
    procedure Unlock; inline;
    function GetMemory(Zero: Boolean): Pointer;
    procedure FreeMemory(P: Pointer);
    procedure Clear;

    property MaxFreeBlocks: Integer read FMaxFreeBlocks write SetMaxFreeBlocks;

    property FreeMemoryBlockList: TList read FFreeMemoryBlockList;
    property UsedMemoryBlockList: TList read FUsedMemoryBlockList;
    property BlockSize: Integer read FBlockSize;
    property FreeBlocks: Integer read GetFreeBlocks;
    property FreeBlocksSize: Integer read GetFreeBlocksSize;
    property UsedBlocks: Integer read GetUsedBlocks;
    property UsedBlocksSize: Integer read GetUsedBlocksSize;
  end;

implementation

{ TIocpMemoryPool }

constructor TIocpMemoryPool.Create(BlockSize, MaxFreeBlocks: Integer);
begin
  // ���С��64�ֽڶ��룬������ִ��Ч�����
  if (BlockSize mod 64 = 0) then
    FBlockSize := BlockSize
  else
    FBlockSize := (BlockSize div 64) * 64 + 64;
    
  FMaxFreeBlocks := MaxFreeBlocks;
  FFreeMemoryBlockList := TList.Create;
  FUsedMemoryBlockList := TList.Create;
  FLocker := TCriticalSection.Create;
  {$ifdef __HEAP_ALLOC__}
  FHeapHandle := GetProcessHeap;
  {$endif}
  FRefCount := 1;
end;

destructor TIocpMemoryPool.Destroy;
begin
  Clear;

  FFreeMemoryBlockList.Free;
  FUsedMemoryBlockList.Free;
  FLocker.Free;
  
  inherited Destroy;
end;

procedure TIocpMemoryPool.Lock;
begin
  FLocker.Enter;
end;

procedure TIocpMemoryPool.Unlock;
begin
  FLocker.Leave;
end;

function TIocpMemoryPool.RealAlloc(Size: Integer; Zero: Boolean): Pointer;
begin
  {$ifdef __HEAP_ALLOC__}
  Result := HeapAlloc(FHeapHandle, HEAP_ALLOC_FLAG[Zero], Size);
  {$else}
  GetMem(Result, Size);
  if (Result <> nil) and Zero then
    FillChar(Result^, Size, 0);
  {$endif}
end;

procedure TIocpMemoryPool.RealFree(P: Pointer);
begin
  {$ifdef __HEAP_ALLOC__}
  HeapFree(FHeapHandle, 0, P);
  {$else}
  FreeMem(P);
  {$endif}
end;

function TIocpMemoryPool.GetMemory(Zero: Boolean): Pointer;
begin
  Result := nil;

  Lock;
  try
    // �ӿ����ڴ���б���ȡһ��
    if (FFreeMemoryBlockList.Count > 0) then
    begin
      Result := FFreeMemoryBlockList[FFreeMemoryBlockList.Count - 1];
      FFreeMemoryBlockList.Delete(FFreeMemoryBlockList.Count - 1);
    end;

    // ���û�п����ڴ�飬�����µ��ڴ��
    if (Result = nil) then
      Result := RealAlloc(FBlockSize, Zero);

    // ��ȡ�õ��ڴ�������ʹ���ڴ���б�
    if (Result <> nil) then
      FUsedMemoryBlockList.Add(Result);
  finally
    Unlock;
  end;

  if (Result = nil) then
    raise Exception.CreateFmt('�����ڴ��ʧ�ܣ����С: %d', [FBlockSize]);
end;

procedure TIocpMemoryPool.FreeMemory(P: Pointer);
begin
  if (P = nil) then Exit;

  Lock;
  try
    // ����ʹ���ڴ���б����Ƴ��ڴ��
    if (FUsedMemoryBlockList.Extract(P) = nil) then Exit;

    // ����������ڴ��û�г��꣬���ڴ��ŵ������ڴ���б���
    if (FFreeMemoryBlockList.Count < FMaxFreeBlocks) then
      FFreeMemoryBlockList.Add(P)
    // �����ͷ��ڴ�
    else
      RealFree(P);
  finally
    Unlock;
  end;
end;

procedure TIocpMemoryPool.Clear;
var
  P: Pointer;
begin
  Lock;

  try
    // ��տ����ڴ�
    while (FFreeMemoryBlockList.Count > 0) do
    begin
      P := FFreeMemoryBlockList[FFreeMemoryBlockList.Count - 1];
      if (P <> nil) then
        RealFree(P);
      FFreeMemoryBlockList.Delete(FFreeMemoryBlockList.Count - 1);
    end;

    // �����ʹ���ڴ�
    while (FUsedMemoryBlockList.Count > 0) do
    begin
      P := FUsedMemoryBlockList[FUsedMemoryBlockList.Count - 1];
      if (P <> nil) then
        RealFree(P);
      FUsedMemoryBlockList.Delete(FUsedMemoryBlockList.Count - 1);
    end;
  finally
    Unlock;
  end;
end;

function TIocpMemoryPool.GetFreeBlocks: Integer;
begin
  Result := FFreeMemoryBlockList.Count;
end;

function TIocpMemoryPool.GetFreeBlocksSize: Integer;
begin
  Result := FFreeMemoryBlockList.Count * FBlockSize;
end;

function TIocpMemoryPool.GetUsedBlocks: Integer;
begin
  Result := FUsedMemoryBlockList.Count;
end;

function TIocpMemoryPool.GetUsedBlocksSize: Integer;
begin
  Result := FUsedMemoryBlockList.Count * FBlockSize;
end;

procedure TIocpMemoryPool.SetMaxFreeBlocks(MaxFreeBlocks: Integer);
begin
  Lock;
  FMaxFreeBlocks := MaxFreeBlocks;
  Unlock;
end;

end.
