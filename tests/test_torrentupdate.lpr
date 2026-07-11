program TestTorrentUpdate;

{$mode objfpc}{$H+}

uses
  SysUtils, TorrentUpdate;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function Torrent(Id: Integer): TTorrentSnapshot;
begin
  Result.Id:=Id;
  Result.Name:=Format('Torrent %d', [Id]);
  Result.Status:=4;
  Result.RateDownload:=100;
  Result.RateUpload:=50;
  Result.SizeWhenDone:=1000;
  Result.LeftUntilDone:=500;
  Result.Eta:=10;
  Result.AddedDate:=1000 + Id;
  Result.DownloadDir:='/downloads';
  Result.Labels:='test';
end;

procedure TestNoChanges;
var
  Current, Incoming: TTorrentSnapshots;
  Update: TTorrentUpdateResult;
begin
  SetLength(Current, 1);
  Current[0]:=Torrent(1);
  Incoming:=Copy(Current);
  Update:=CompareSnapshots(Current, Incoming, tsDownloadRate, True);
  Check(Length(Update.ChangedIds) = 0, 'unchanged snapshot reported a change');
  Check(not Update.SortInvalidated, 'unchanged snapshot invalidated sorting');
end;

procedure TestDynamicChanges;
var
  Current, Incoming: TTorrentSnapshots;
  Update: TTorrentUpdateResult;
begin
  SetLength(Current, 1);
  Current[0]:=Torrent(1);
  Incoming:=Copy(Current);
  Incoming[0].RateDownload:=101;
  Update:=CompareSnapshots(Current, Incoming, tsName, False);
  Check(Length(Update.ChangedIds) = 1, 'speed change was not detected');
  Check(not Update.SortInvalidated, 'name sort invalidated by speed change');
  Update:=CompareSnapshots(Current, Incoming, tsDownloadRate, False);
  Check(Update.SortInvalidated, 'speed sort not invalidated by speed change');
  Incoming[0].Status:=6;
  Update:=CompareSnapshots(Current, Incoming, tsStatus, False);
  Check(Update.SortInvalidated, 'status sort not invalidated by status change');
end;

procedure TestStructuralChanges;
var
  Current, Incoming: TTorrentSnapshots;
  Update: TTorrentUpdateResult;
begin
  SetLength(Current, 1);
  Current[0]:=Torrent(1);
  SetLength(Incoming, 2);
  Incoming[0]:=Current[0];
  Incoming[1]:=Torrent(2);
  Update:=CompareSnapshots(Current, Incoming, tsNone, True);
  Check((Length(Update.AddedIds) = 1) and Update.FullRefreshRequired,
    'torrent addition was not structural');
  SetLength(Incoming, 0);
  Update:=CompareSnapshots(Current, Incoming, tsNone, True);
  Check((Length(Update.RemovedIds) = 1) and Update.FullRefreshRequired,
    'torrent removal was not structural');
end;

procedure TestGroupingAndGeneration;
var
  Current, Incoming: TTorrentSnapshots;
  Update: TTorrentUpdateResult;
begin
  SetLength(Current, 1);
  Current[0]:=Torrent(1);
  Incoming:=Copy(Current);
  Incoming[0].DownloadDir:='/other';
  Update:=CompareSnapshots(Current, Incoming, tsName, True);
  Check(Update.GroupingInvalidated, 'path change did not invalidate grouping');
  Check(IsCurrentGeneration(5, 5), 'current generation rejected');
  Check(not IsCurrentGeneration(4, 5), 'stale generation accepted');
end;

procedure TestLargeSparseUpdate;
var
  Current, Incoming: TTorrentSnapshots;
  I: Integer;
  Update: TTorrentUpdateResult;
begin
  SetLength(Current, 1700);
  for I:=0 to High(Current) do
    Current[I]:=Torrent(I + 1);
  Incoming:=Copy(Current);
  for I:=0 to 9 do
    Inc(Incoming[I * 100].RateUpload);
  Update:=CompareSnapshots(Current, Incoming, tsUploadRate, False);
  Check(Length(Update.ChangedIds) = 10, 'sparse update count was incorrect');
  Check(Update.SortInvalidated, 'dynamic sort was not invalidated');
end;

begin
  TestNoChanges;
  TestDynamicChanges;
  TestStructuralChanges;
  TestGroupingAndGeneration;
  TestLargeSparseUpdate;
  WriteLn('test_torrentupdate: all tests passed');
end.
