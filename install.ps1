# tcast installer (Windows) — downloads a prebuilt tcast.exe from GitHub
# Releases, verifies its sha256, installs it under %LOCALAPPDATA%, and adds it
# to the per-user PATH.
#
#   powershell -c "irm https://raw.githubusercontent.com/EijunnN/share-tui/main/install.ps1 | iex"
#
# Env overrides:
#   $env:TCAST_VERSION       release tag to install (default: latest)
#   $env:TCAST_INSTALL_DIR   target directory (default: %LOCALAPPDATA%\Programs\tcast)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = 'EijunnN/share-tui'
$Bin  = 'tcast'
$Version = if ($env:TCAST_VERSION) { $env:TCAST_VERSION } else { 'latest' }

$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
  'AMD64' { 'x86_64' }
  'ARM64' { 'aarch64' }
  default { throw "unsupported architecture: $($env:PROCESSOR_ARCHITECTURE)" }
}
$target = "$arch-pc-windows-msvc"
$asset  = "$Bin-$target.zip"
$base   = "https://github.com/$Repo/releases"
$url    = if ($Version -eq 'latest') { "$base/latest/download/$asset" } else { "$base/download/$Version/$asset" }

$tmp = Join-Path $env:TEMP ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

Write-Host "downloading $asset ..."
Invoke-WebRequest -Uri $url -OutFile "$tmp\$asset" -UseBasicParsing

# Verify checksum when available.
try {
  Invoke-WebRequest -Uri "$url.sha256" -OutFile "$tmp\$asset.sha256" -UseBasicParsing
  $want = ((Get-Content "$tmp\$asset.sha256") -split '\s+')[0]
  $got  = (Get-FileHash "$tmp\$asset" -Algorithm SHA256).Hash
  if ($want -and ($want.ToLower() -ne $got.ToLower())) { throw "checksum mismatch for $asset" }
  Write-Host "checksum ok"
} catch {
  Write-Warning "checksum not verified: $($_.Exception.Message)"
}

Expand-Archive -Path "$tmp\$asset" -DestinationPath $tmp -Force
$exe = Get-ChildItem -Path $tmp -Recurse -Filter "$Bin.exe" | Select-Object -First 1
if (-not $exe) { throw "$Bin.exe not found in archive" }

$dir = if ($env:TCAST_INSTALL_DIR) { $env:TCAST_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "Programs\tcast" }
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item $exe.FullName (Join-Path $dir "$Bin.exe") -Force
Write-Host "installed: $dir\$Bin.exe"

# Persist on the per-user PATH.
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $dir) {
  [Environment]::SetEnvironmentVariable('Path', "$userPath;$dir", 'User')
  $env:Path = "$env:Path;$dir"
  Write-Host "added $dir to your PATH (open a NEW terminal for it to take effect)"
}

Write-Host ""
Write-Host "done — try:  $Bin --help"
Write-Host "set your relay once:  $Bin config set-relay wss://relay.example.com"
