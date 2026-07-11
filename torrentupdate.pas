unit TorrentUpdate;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TTorrentSortField = (tsNone, tsName, tsStatus, tsDownloadRate, tsUploadRate,
    tsProgress, tsEta, tsAddedDate, tsPath, tsLabel);
  TTorrentUpdateField = (tufStatic, tufStatus, tufRates, tufProgress, tufError,
    tufPath, tufLabels, tufDates);
  TTorrentUpdateFields = set of TTorrentUpdateField;

  TTorrentSnapshot = record
    Id: Integer;
    Name: string;
    Status: Integer;
    RateDownload: Int64;
    RateUpload: Int64;
    LeftUntilDone: Int64;
    SizeWhenDone: Int64;
    Eta: Integer;
    ErrorString: string;
    AddedDate: Int64;
    DownloadDir: string;
    Labels: string;
  end;

  TTorrentSnapshots = array of TTorrentSnapshot;
  TIntegerArray = array of Integer;

  TTorrentUpdateResult = record
    AddedIds: TIntegerArray;
    RemovedIds: TIntegerArray;
    ChangedIds: TIntegerArray;
    ChangedFields: TTorrentUpdateFields;
    SortInvalidated: Boolean;
    GroupingInvalidated: Boolean;
    FullRefreshRequired: Boolean;
  end;

function CompareSnapshots(const Current, Incoming: TTorrentSnapshots;
  SortField: TTorrentSortField; GroupingEnabled: Boolean): TTorrentUpdateResult;
function IsCurrentGeneration(ResultGeneration, RequestedGeneration: QWord): Boolean;

implementation

procedure AddId(var Values: TIntegerArray; Id: Integer);
var
  LengthBefore: Integer;
begin
  LengthBefore:=Length(Values);
  SetLength(Values, LengthBefore + 1);
  Values[LengthBefore]:=Id;
end;

function FindIndex(const Snapshots: TTorrentSnapshots; const Index: TStringList;
  Id: Integer): Integer;
var
  Position: Integer;
begin
  if Index.Find(IntToStr(Id), Position) then
    Result:=PtrInt(Index.Objects[Position])
  else
    Result:=-1;
end;

procedure BuildIndex(const Snapshots: TTorrentSnapshots; Index: TStringList);
var
  I: Integer;
begin
  for I:=0 to High(Snapshots) do
    Index.AddObject(IntToStr(Snapshots[I].Id), TObject(PtrInt(I)));
end;

function Changed(const Current, Incoming: TTorrentSnapshot): TTorrentUpdateFields;
begin
  Result:=[];
  if Current.Name <> Incoming.Name then
    Include(Result, tufStatic);
  if Current.Status <> Incoming.Status then
    Include(Result, tufStatus);
  if (Current.RateDownload <> Incoming.RateDownload) or
    (Current.RateUpload <> Incoming.RateUpload) then
    Include(Result, tufRates);
  if (Current.LeftUntilDone <> Incoming.LeftUntilDone) or
    (Current.SizeWhenDone <> Incoming.SizeWhenDone) or
    (Current.Eta <> Incoming.Eta) then
    Include(Result, tufProgress);
  if Current.ErrorString <> Incoming.ErrorString then
    Include(Result, tufError);
  if Current.AddedDate <> Incoming.AddedDate then
    Include(Result, tufDates);
  if Current.DownloadDir <> Incoming.DownloadDir then
    Include(Result, tufPath);
  if Current.Labels <> Incoming.Labels then
    Include(Result, tufLabels);
end;

function SortAffected(SortField: TTorrentSortField;
  Fields: TTorrentUpdateFields): Boolean;
begin
  case SortField of
    tsName: Result:=tufStatic in Fields;
    tsStatus: Result:=tufStatus in Fields;
    tsDownloadRate, tsUploadRate: Result:=tufRates in Fields;
    tsProgress, tsEta: Result:=tufProgress in Fields;
    tsAddedDate: Result:=tufDates in Fields;
    tsPath: Result:=tufPath in Fields;
    tsLabel: Result:=tufLabels in Fields;
    else Result:=False;
  end;
end;

function CompareSnapshots(const Current, Incoming: TTorrentSnapshots;
  SortField: TTorrentSortField; GroupingEnabled: Boolean): TTorrentUpdateResult;
var
  CurrentIndex, IncomingIndex: TStringList;
  I, CurrentPosition: Integer;
  Fields: TTorrentUpdateFields;
begin
  Result.ChangedFields:=[];
  CurrentIndex:=TStringList.Create;
  IncomingIndex:=TStringList.Create;
  try
    CurrentIndex.Sorted:=True;
    CurrentIndex.Duplicates:=dupError;
    IncomingIndex.Sorted:=True;
    IncomingIndex.Duplicates:=dupError;
    BuildIndex(Current, CurrentIndex);
    BuildIndex(Incoming, IncomingIndex);

    for I:=0 to High(Incoming) do begin
      CurrentPosition:=FindIndex(Current, CurrentIndex, Incoming[I].Id);
      if CurrentPosition < 0 then begin
        AddId(Result.AddedIds, Incoming[I].Id);
        Result.SortInvalidated:=True;
        Result.GroupingInvalidated:=GroupingEnabled;
        Result.FullRefreshRequired:=True;
      end
      else begin
        Fields:=Changed(Current[CurrentPosition], Incoming[I]);
        if Fields <> [] then begin
          AddId(Result.ChangedIds, Incoming[I].Id);
          Result.ChangedFields:=Result.ChangedFields + Fields;
          Result.SortInvalidated:=Result.SortInvalidated or SortAffected(SortField, Fields);
          Result.GroupingInvalidated:=Result.GroupingInvalidated or
            (GroupingEnabled and (Fields * [tufPath, tufLabels] <> []));
        end;
      end;
    end;

    for I:=0 to High(Current) do
      if FindIndex(Incoming, IncomingIndex, Current[I].Id) < 0 then begin
        AddId(Result.RemovedIds, Current[I].Id);
        Result.SortInvalidated:=True;
        Result.GroupingInvalidated:=GroupingEnabled;
        Result.FullRefreshRequired:=True;
      end;
  finally
    IncomingIndex.Free;
    CurrentIndex.Free;
  end;
end;

function IsCurrentGeneration(ResultGeneration, RequestedGeneration: QWord): Boolean;
begin
  Result:=ResultGeneration = RequestedGeneration;
end;

end.
