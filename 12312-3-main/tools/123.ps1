#requires -Version 5.1
<#
    staging + patch
    names: driver.sys, mapper.exe, 123.exe, 123.sys
#>
[CmdletBinding()]
param(
    [string]$Root = $PSScriptRoot,
    [switch]$Session,
    [switch]$UnsafeFull,
    [switch]$PatchIntel,
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'
$ProgressPreference   = 'SilentlyContinue'

function Write-Step([string]$Text) { Write-Host ("[*] " + $Text) -ForegroundColor DarkGray }
function Write-Ok  ([string]$Text) { Write-Host ("[+] " + $Text) -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host ("[!] " + $Text) -ForegroundColor Yellow }

$candidates = @($Root, (Split-Path $Root -Parent)) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
function Find-Source([string]$Name) {
    foreach ($dir in $candidates) {
        $p = Join-Path $dir $Name
        if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
    }
    return $null
}

$binSrc    = Find-Source 'driver.bin'
$sysSrc    = Find-Source '123.sys'
$mapperSrc = Find-Source 'mapper.exe'
$clientSrc = Find-Source '123.exe'

foreach ($pair in @(@('driver', $binSrc), @('sys', $sysSrc), @('mapper', $mapperSrc), @('client', $clientSrc))) {
    if (-not $pair[1]) { throw ("missing: " + $pair[0]) }
}

$runDir = Join-Path $Root 'run'
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$driverPath = Join-Path $runDir 'driver.sys'
$sysPath    = Join-Path $runDir '123.sys'

if ($Restore) {
    foreach ($f in @($driverPath, $sysPath)) {
        if (Test-Path -LiteralPath ($f + '.orig')) {
            Copy-Item -LiteralPath ($f + '.orig') -Destination $f -Force
            Write-Ok ("restored " + (Split-Path $f -Leaf))
        }
    }
    return
}

$keyPatches = @(
    @{Off=0x5F5; Hex='0F84C8000000'},
    @{Off=0x5FE; Hex='0F85BF000000'},
    @{Off=0x9E5; Hex='0F8439010000'},
    @{Off=0x9EE; Hex='0F8530010000'},
    @{Off=0x3164; Hex='742A'},
    @{Off=0x3169; Hex='7525'}
)

$statePatches = @(
    @{Off=0x48F;  Hex='0F85CB000000'},
    @{Off=0x498;  Hex='0F84C2000000'},
    @{Off=0x5D0;  Hex='0F85F6000000'},
    @{Off=0x5D9;  Hex='0F84ED000000'},
    @{Off=0x735;  Hex='0F850D020000'},
    @{Off=0x746;  Hex='0F84FC010000'},
    @{Off=0x80E;  Hex='0F8434010000'},
    @{Off=0x9A8;  Hex='0F858A010000'},
    @{Off=0x9B9;  Hex='0F8479010000'},
    @{Off=0x9C9;  Hex='0F8569010000'},
    @{Off=0x39CB; Hex='7407'}
)

$structuralPatches = @(
    @{Off=0x313A; Hex='7479'}, @{Off=0x3143; Hex='7270'}, @{Off=0x314C; Hex='7267'},
    @{Off=0x3158; Hex='750C'}, @{Off=0x33AF; Hex='0F84F5000000'},
    @{Off=0x3408; Hex='0F8785000000'}, @{Off=0x3426; Hex='7870'},
    @{Off=0x34DD; Hex='750D'}, @{Off=0x354B; Hex='0F849E000000'},
    @{Off=0x3556; Hex='0F8493000000'}, @{Off=0x3561; Hex='0F8488000000'},
    @{Off=0x356F; Hex='777E'}, @{Off=0x388B; Hex='0F849E000000'},
    @{Off=0x3896; Hex='0F8493000000'}, @{Off=0x38A1; Hex='0F8488000000'},
    @{Off=0x38AF; Hex='777E'}, @{Off=0x362E; Hex='0F842C020000'},
    @{Off=0x3639; Hex='0F8421020000'}, @{Off=0x3654; Hex='0F8706020000'},
    @{Off=0x371A; Hex='0F8806010000'}, @{Off=0x3728; Hex='0F82F8000000'},
    @{Off=0x3823; Hex='7424'}, @{Off=0x3831; Hex='7424'}
)

$intelPatches = @(
    @{Off=0x20D7; Hex='0F8488000000'}, @{Off=0x210E; Hex='7517'},
    @{Off=0x221F; Hex='0F845C010000'}, @{Off=0x2228; Hex='0F8453010000'},
    @{Off=0x2551; Hex='7412'}, @{Off=0x268E; Hex='751E'},
    @{Off=0x29C2; Hex='0F84AE000000'}, @{Off=0x29CB; Hex='0F84A5000000'}
)

function Convert-HexToBytes([string]$Hex) {
    $out = New-Object byte[] ($Hex.Length / 2)
    for ($i = 0; $i -lt $out.Length; $i++) { $out[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16) }
    return $out
}

function Invoke-PatchSet([string]$Path, $Set) {
    if (-not (Test-Path -LiteralPath $Path)) { throw ("no file: " + $Path) }
    if (-not (Test-Path -LiteralPath ($Path + '.orig'))) {
        Copy-Item -LiteralPath $Path -Destination ($Path + '.orig') -Force
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $n = 0
    foreach ($p in $Set) {
        $off  = [int]$p.Off
        $want = Convert-HexToBytes $p.Hex
        $ok = $true
        for ($i = 0; $i -lt $want.Length; $i++) {
            if (($off + $i) -ge $bytes.Length -or $bytes[$off + $i] -ne $want[$i]) { $ok = $false; break }
        }
        if (-not $ok) { continue }
        for ($i = 0; $i -lt $want.Length; $i++) { $bytes[$off + $i] = 0x90 }
        $n++
    }
    [IO.File]::WriteAllBytes($Path, $bytes)
    return $n
}

function Copy-Retry([string]$From, [string]$To, [int]$Tries = 6) {
    for ($a = 1; $a -le $Tries; $a++) {
        try {
            Copy-Item -LiteralPath $From -Destination $To -Force -ErrorAction Stop
        } catch [System.IO.IOException] {
            if ($a -eq $Tries) { throw }
            Start-Sleep -Milliseconds (250 * $a)
        }
    }
}

# an overlay already running (any copy) keeps run\123.exe locked and makes the
# new and the old menu blink on top of each other: kill every client copy first
$names = @('123', 'client', 'q9ateua8xt')
$running = @(Get-Process -Name $names -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    Write-Step ("stopping " + $running.Count + " client process(es)")
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 900
    $left = @(Get-Process -Name $names -ErrorAction SilentlyContinue)
    if ($left.Count -gt 0) {
        Write-Warn ("still alive: pid " + ($left.Id -join ',') + " (elevated) - close it via Task Manager")
        throw "client is still running, staging aborted"
    }
}

Copy-Retry $binSrc    $driverPath
Copy-Retry $sysSrc    $sysPath
Copy-Retry $mapperSrc (Join-Path $runDir 'mapper.exe')
Copy-Retry $clientSrc (Join-Path $runDir '123.exe')

$assetsSrc = if (Test-Path -LiteralPath (Join-Path $Root 'assets')) { Join-Path $Root 'assets' } else { Find-Source 'assets' }
if ($assetsSrc) {
    Copy-Item -LiteralPath $assetsSrc -Destination (Join-Path $runDir 'assets') -Recurse -Force
    Write-Step 'assets staged'
}

Write-Step 'staging'
$c1 = Invoke-PatchSet $driverPath $keyPatches
if ($Session)    { $c2 = Invoke-PatchSet $driverPath $statePatches; Write-Step ("state " + $c2) }
if ($UnsafeFull) { $c3 = Invoke-PatchSet $driverPath $structuralPatches; Write-Warn ("full " + $c3) }
if ($PatchIntel) { $c4 = Invoke-PatchSet $sysPath $intelPatches; Write-Step ("sys " + $c4) }

Write-Ok ("ready: " + $c1)
