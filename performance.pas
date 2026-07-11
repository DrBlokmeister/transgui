unit Performance;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

function TimingStart: QWord;
function TimingElapsed(StartTick: QWord): QWord;
procedure TimingLog(const MessageText: string);

implementation

{$ifdef TRANSGUI_TIMING}
uses
  LCLProc;
{$endif}

function TimingStart: QWord;
begin
  {$ifdef TRANSGUI_TIMING}
  Result:=GetTickCount64;
  {$else}
  Result:=0;
  {$endif}
end;

function TimingElapsed(StartTick: QWord): QWord;
begin
  {$ifdef TRANSGUI_TIMING}
  Result:=GetTickCount64 - StartTick;
  {$else}
  Result:=0;
  {$endif}
end;

procedure TimingLog(const MessageText: string);
begin
  {$ifdef TRANSGUI_TIMING}
  DebugLn('[timing] ' + MessageText);
  {$endif}
end;

end.
