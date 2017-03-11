unit Iocp.ApiFix;

interface

uses
  Windows;

(*

Delphi�Դ���IOCP��صļ������������Ǵ�ģ�
��32λ�����²�������⣬����64λ������ʹ���

Delphi XE2֧��64λ���룬����XE2ֱ��Update4�Ķ��嶼�Ǵ�ģ�ϣ���Ժ�ٷ�������

// ����Delphi�Ĵ����壬
// CompletionKey: DWORD
// DWORD������32λ����64λ�����ж���4�ֽڣ�MSDN����ȷ�Ķ�����ULONG_PTR
// ULONG_PTR��32λ��������4�ֽڣ���64λ��������8�ֽ�
function CreateIoCompletionPort(FileHandle, ExistingCompletionPort: THandle;
  CompletionKey, NumberOfConcurrentThreads: DWORD): THandle; stdcall;
{$EXTERNALSYM CreateIoCompletionPort}
function GetQueuedCompletionStatus(CompletionPort: THandle;
  var lpNumberOfBytesTransferred, lpCompletionKey: DWORD;
  var lpOverlapped: POverlapped; dwMilliseconds: DWORD): BOOL; stdcall;
{$EXTERNALSYM GetQueuedCompletionStatus}
function PostQueuedCompletionStatus(CompletionPort: THandle; dwNumberOfBytesTransferred: DWORD;
  dwCompletionKey: DWORD; lpOverlapped: POverlapped): BOOL; stdcall;
{$EXTERNALSYM PostQueuedCompletionStatus}
*)

// ���������Լ�����MSDN����ĵ�������Ķ���

function CreateIoCompletionPort(FileHandle, ExistingCompletionPort: THandle;
  CompletionKey: ULONG_PTR; NumberOfConcurrentThreads: DWORD): THandle; stdcall;

function GetQueuedCompletionStatus(CompletionPort: THandle;
  var lpNumberOfBytesTransferred: DWORD; var lpCompletionKey: ULONG_PTR;
  var lpOverlapped: POverlapped; dwMilliseconds: DWORD): BOOL; stdcall;

function PostQueuedCompletionStatus(CompletionPort: THandle; dwNumberOfBytesTransferred: DWORD;
  dwCompletionKey: ULONG_PTR; lpOverlapped: POverlapped): BOOL; stdcall;

implementation

function CreateIoCompletionPort; external kernel32 name 'CreateIoCompletionPort';
function GetQueuedCompletionStatus; external kernel32 name 'GetQueuedCompletionStatus';
function PostQueuedCompletionStatus; external kernel32 name 'PostQueuedCompletionStatus';

end.
