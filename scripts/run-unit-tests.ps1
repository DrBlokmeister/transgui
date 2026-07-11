$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$fpc = 'C:\lazarus\fpc\3.2.2\bin\i386-win32\fpc.exe'
if (-not (Test-Path $fpc)) {
  $fpc = 'fpc'
}

Push-Location $root
try {
  & $fpc '-Fu.' 'tests\test_torrentupdate.lpr'
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
  & '.\tests\test_torrentupdate.exe'
  exit $LASTEXITCODE
}
finally {
  Pop-Location
}
