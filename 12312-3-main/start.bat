@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "RUN=%ROOT%\run"
set "PS1=%ROOT%\tools\123.ps1"
set "PS_FLAGS="
set "NO_CLIENT="
set "FIX_BLOCKLIST="
set "LOOT_ONLY="
set "AIM_ONLY="
:parse
if "%~1"=="" goto after_parse
if /i "%~1"=="--s" set "PS_FLAGS=%PS_FLAGS% -Session" & shift & goto parse
if /i "%~1"=="--u" set "PS_FLAGS=%PS_FLAGS% -UnsafeFull" & shift & goto parse
if /i "%~1"=="--i" set "PS_FLAGS=%PS_FLAGS% -PatchIntel" & shift & goto parse
if /i "%~1"=="--n" set "NO_CLIENT=1" & shift & goto parse
if /i "%~1"=="--b" set "FIX_BLOCKLIST=1" & shift & goto parse
if /i "%~1"=="--loot" set "LOOT_ONLY=1" & shift & goto parse
if /i "%~1"=="--aim" set "AIM_ONLY=1" & shift & goto parse
if /i "%~1"=="--r" goto do_restore
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
echo [warn] unknown option: %~1
goto usage
:after_parse
net session >nul 2>&1
if not errorlevel 1 goto admin_ok
if not "%~1"=="" goto elevate_args
echo [*] requesting administrator rights...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" 2>nul
exit /b
:elevate_args
echo [*] requesting administrator rights...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs" 2>nul
exit /b
:admin_ok
if not defined AIM_ONLY goto loot_check
set "ARMORE3_AIM=1"
call :armore3_patch
endlocal
exit /b %errorlevel%
:loot_check
if not defined LOOT_ONLY goto ps1_check
call :loot_launch
endlocal
exit /b %errorlevel%
:ps1_check
if exist "%PS1%" goto ps1_ok
echo [-] missing: "%PS1%"
goto fail
:ps1_ok
if not defined FIX_BLOCKLIST goto blocklist_check
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CI\Config" /v VulnerableDriverBlocklistEnable /t REG_DWORD /d 0 /f >nul 2>&1
if errorlevel 1 goto blocklist_failed
echo [+] reg ok
echo [warn] reboot required
goto blocklist_check
:blocklist_failed
echo [-] reg write failed
:blocklist_check
set "BL="
for /f "tokens=3" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\CI\Config" /v VulnerableDriverBlocklistEnable 2^>nul ^| findstr /i VulnerableDriverBlocklistEnable') do set "BL=%%A"
if not defined BL goto blocklist_done
if "!BL!"=="0x0" goto blocklist_done
echo [warn] blocklist on: !BL!
:blocklist_done
if not defined FIX_BLOCKLIST goto patch_stage
echo [warn] reboot, then run again
endlocal
exit /b 0
:patch_stage
call :armore3_patch
if errorlevel 1 goto fail
echo [*] stage...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Root "%ROOT%" %PS_FLAGS%
if errorlevel 1 goto fail
if not exist "%TEMP%\focus.key" goto key_clean
del /f /q "%TEMP%\focus.key" >nul 2>&1
:key_clean
echo [*] start...
pushd "%RUN%"
start "" /b "%RUN%\mapper.exe" "%RUN%\123.sys" "%RUN%\driver.sys"
popd
echo [*] wait...
set "WAIT=0"
:wait_key
if exist "%TEMP%\focus.key" goto have_key
set /a WAIT+=1
if !WAIT! GEQ 30 goto no_key
ping -n 2 127.0.0.1 >nul
goto wait_key
:have_key
echo [+] ok
goto client
:no_key
echo [warn] timeout
:client
if defined NO_CLIENT goto done
if exist "%RUN%\123.exe" goto client_ok
goto done
:client_ok
tasklist /fi "imagename eq 123.exe" 2>nul | find /i "123.exe" >nul
if not errorlevel 1 goto client_running
echo [*] client...
pushd "%RUN%"
start "" "%RUN%\123.exe"
popd
goto done
:client_running
echo [+] running
:done
echo [+] end
endlocal
exit /b 0
:do_restore
net session >nul 2>&1
if not errorlevel 1 goto restore_admin
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '--r' -Verb RunAs" 2>nul
exit /b
:restore_admin
if not exist "%ROOT%\123.exe.stock" goto restore_drv
copy /y "%ROOT%\123.exe.stock" "%ROOT%\123.exe" >nul 2>&1
if exist "%RUN%\123.exe" copy /y "%ROOT%\123.exe.stock" "%RUN%\123.exe" >nul 2>&1
echo [+] client restored
:restore_drv
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Root "%ROOT%" -Restore
endlocal
exit /b 0
:loot_launch
rem --- build with FastLoot: the Loader's RobRun.exe (see CHANGES_armore3.md, sec. 5)
set "LOADER_BAT="
if defined ARMORE3_LOADER set "LOADER_BAT=%ARMORE3_LOADER%"
if not defined LOADER_BAT if exist "%ROOT%\..\..\Loader\start.bat" set "LOADER_BAT=%ROOT%\..\..\Loader\start.bat"
if not defined LOADER_BAT if exist "%ROOT%\..\Loader\start.bat" set "LOADER_BAT=%ROOT%\..\Loader\start.bat"
if not defined LOADER_BAT goto loot_missing
echo [*] FastLoot build (RobRun.exe) - launching Loader...
call "%LOADER_BAT%" nopause
exit /b %errorlevel%
:loot_missing
echo [-] loader not found (Loader\start.bat)
echo     set ARMORE3_LOADER=<path to Loader\start.bat> and retry
exit /b 1
:usage
echo.
echo   start.bat [options]
echo.
echo   (no options)  apply patches, stage, launch
echo   --s   state checks
echo   --u   full (bugcheck risk)
echo   --i   intel patch
echo   --n   driver only
echo   --b   blocklist off (reboot)
echo   --loot  launch the FastLoot build (Loader\RobRun.exe)
echo   --aim   fix aim assist settings in %%APPDATA%%\focus_robrun.cfg
echo   --r   restore
echo.
endlocal
exit /b 1
:fail
echo [-] fail
endlocal
exit /b 1
:armore3_patch
set "ARMORE3_BAT=%~f0"
set "ARMORE3_ROOT=%ROOT%"
powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand JABmAD0AJABlAG4AdgA6AEEAUgBNAE8AUgBFADMAXwBCAEEAVAA7ACQAdAA9AFsASQBPAC4ARgBpAGwAZQBdADoAOgBSAGUAYQBkAEEAbABsAFQAZQB4AHQAKAAkAGYAKQA7ACQAYQA9ACQAdAAuAEkAbgBkAGUAeABPAGYAKABbAGMAaABhAHIAXQAzADUAKwBbAGMAaABhAHIAXQA5ADUAKwBbAGMAaABhAHIAXQA5ADUAKwBbAGMAaABhAHIAXQA2ADUAKwBbAGMAaABhAHIAXQA4ADIAKwBbAGMAaABhAHIAXQA3ADcAKwBbAGMAaABhAHIAXQA3ADkAKwBbAGMAaABhAHIAXQA4ADIAKwBbAGMAaABhAHIAXQA2ADkAKwBbAGMAaABhAHIAXQA1ADEAKwBbAGMAaABhAHIAXQA5ADUAKwBbAGMAaABhAHIAXQA2ADYAKwBbAGMAaABhAHIAXQA2ADkAKwBbAGMAaABhAHIAXQA3ADEAKwBbAGMAaABhAHIAXQA3ADMAKwBbAGMAaABhAHIAXQA3ADgAKwBbAGMAaABhAHIAXQA5ADUAKwBbAGMAaABhAHIAXQA5ADUAKQA7ACQAYgA9ACQAdAAuAEkAbgBkAGUAeABPAGYAKABbAGMAaABhAHIAXQAzADUAKwBbAGMAaABhAHIAXQA5ADUAKwBbAGMAaABhAHIAXQA5ADUAKwBbAGMAaABhAHIAXQA2ADUAKwBbAGMAaABhAHIAXQA4ADIAKwBbAGMAaABhAHIAXQA3ADcAKwBbAGMAaABhAHIAXQA3ADkAKwBbAGMAaABhAHIAXQA4ADIAKwBbAGMAaABhAHIAXQA2ADkAKwBbAGMAaABhAHIAXQA1ADEAKwBbAGMAaABhAHIAXQA5ADUAKwBbAGMAaABhAHIAXQA2ADkAKwBbAGMAaABhAHIAXQA3ADgAKwBbAGMAaABhAHIAXQA2ADgAKwBbAGMAaABhAHIAXQA5ADUAKwBbAGMAaABhAHIAXQA5ADUAKQA7AGkAZgAoACgAJABhACAALQBsAHQAIAAwACkAIAAtAG8AcgAgACgAJABiACAALQBsAGUAIAAkAGEAKQApAHsAIABXAHIAaQB0AGUALQBIAG8AcwB0ACAAIgBbAGEAcgBtAG8AcgBlADMAXQAgAGIAbABvAGMAawAgAG0AaQBzAHMAaQBuAGcAIgA7ACAAZQB4AGkAdAAgADAAIAB9ADsAJABzAD0AJAB0AC4AUwB1AGIAcwB0AHIAaQBuAGcAKAAkAGEALAAkAGIALQAkAGEAKQA7ACQAbgBsAD0AWwBzAHQAcgBpAG4AZwBdAFsAYwBoAGEAcgBdADEAMwArAFsAcwB0AHIAaQBuAGcAXQBbAGMAaABhAHIAXQAxADAAOwAkAHMAPQAoACgAJABzACAALQBzAHAAbABpAHQAIAAkAG4AbAApACAAfAAgAFMAZQBsAGUAYwB0AC0ATwBiAGoAZQBjAHQAIAAtAFMAawBpAHAAIAAxACkAIAAtAGoAbwBpAG4AIAAkAG4AbAA7ACQAcAA9AEoAbwBpAG4ALQBQAGEAdABoACAAJABlAG4AdgA6AFQARQBNAFAAIAAiAGEAcgBtAG8AcgBlADMAXwBwAGEAdABjAGgALgBwAHMAMQAiADsAWwBJAE8ALgBGAGkAbABlAF0AOgA6AFcAcgBpAHQAZQBBAGwAbABUAGUAeAB0ACgAJABwACwAJABzACwAWwBUAGUAeAB0AC4ARQBuAGMAbwBkAGkAbgBnAF0AOgA6AEEAUwBDAEkASQApADsAJgAgAHAAbwB3AGUAcgBzAGgAZQBsAGwAIAAtAE4AbwBQAHIAbwBmAGkAbABlACAALQBFAHgAZQBjAHUAdABpAG8AbgBQAG8AbABpAGMAeQAgAEIAeQBwAGEAcwBzACAALQBGAGkAbABlACAAJABwADsAZQB4AGkAdAAgACQATABBAFMAVABFAFgASQBUAEMATwBEAEUAOwA=
if errorlevel 1 exit /b 1
exit /b 0
#__ARMORE3_BEGIN__
$ErrorActionPreference='Stop'
$root=$env:ARMORE3_ROOT
if([string]::IsNullOrEmpty($root)){ $root=(Get-Location).Path }
function Log([string]$m){ Write-Host ('[armore3] '+$m) }
$exe=Join-Path $root '123.exe'
$stock=$exe+'.stock'
$buildFile=Join-Path $root '123.exe.build'

# ---------------------------------------------------------------------------
# every patch is a site: A = bytes right before it, W = its original bytes,
# H = the patched bytes, O = offset in the reference build, K = kind
# offsets are searched again on each start, so a rebuilt client whose code
# moved is still patched; cave/build/lea addresses are rebuilt at run time
# ---------------------------------------------------------------------------
$edits=@(
  @{N='watermark'; K='plain'; O=0x157CCC; A='000000C300C079C4286B6ECECAF249F1'; W='6C65616B204073796E63747900'; H='42592061726D6F726533000000'}
  @{N='end-boot'; K='plain'; O=0x8594E; A='006685C0'; W='793C'; H='9090'}
  @{N='end-main'; K='plain'; O=0x85B5C; A='006685C0'; W='7912'; H='9090'}
  @{N='reserve10'; K='plain'; O=0x9809D; A='8578020000488D0568180C0048898580020000488D0562180C00488985880200000F57C0F30F7F45304C896D40'; W='BA06000000488D4D'; H='BA0A000000488D4D'}
  @{N='indexbound'; K='plain'; O=0x93A8D; A='F808000048634838'; W='83F905'; H='83F909'}
  @{N='table-lea'; K='lea'; O=0x93AA0; A='7775F30F100D66450C000F57C0488BC1'; W='488D0D397B0C00'; H='488D0D7D460C00'}
  @{N='build-site'; K='build'; O=0x980B6; A='0000488D0562180C00488985880200000F57C0F30F7F45304C896D40BA06000000488D4D30E8852BFEFF488D4530488985A0000000'; W='488B45300F1085600200000F11000F108D700200000F1148100F1085800200000F1140204883C030488945384C89ADA0000000'; H='E9845E0B0090909090909090909090909090909090909090909090909090909090909090909090909090909090909090909090'}
  @{N='cave'; K='cave'; O=0x14DF3F; A='0000000000488B5C24384883C4205FC3'; W='00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'; H='488B4530488D1596A1000048895000488D1596A1000048895008488D1594A1000048895010488D1590A1000048895018488D158AA1000048895020488D1584A1000048895028488D157FA1000048895030488D157AA1000048895038488D1574A1000048895040488D1571A10000488950484883C050488945384C89ADA0000000E924A1F4FF'}
  @{N='data'; K='data'; O=0x157CE0; A='00C079C4286B6ECECAF249F16C65616B204073796E6374790000000000000000'; W='00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'; H='466F63757320626C75650049636520626C75650056696F6C6574004D696E7400526F736500416D62657200426C61636B0047726179004372696D736F6E005465616C0000FFFE7C31FFFFBF93FFF65C8BFF8BCB2CFF7A57F4FF24A5F5FF181212FFAEA39AFF4A37E2FFB4D421'}
  @{N='aim-keep'; K='plain'; O=0x20E37; A='2BD881FBBC020000'; W='0F867AFFFFFF'; H='E97BFFFFFF90'}
  @{N='aim-write-stock'; K='plain'; O=0x21109; A='488B0848394C2458'; W='7413'; H='7413'}
  @{N='silent-keep'; K='plain'; O=0x726BF; A='0848398DE0000000'; W='7452'; H='EB52'}
  @{N='friend-code'; K='code'; O=0x157F58; A=''; W='000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'; H='505152565741504151415241539CFC807B20000F84B3000000488B73384885F60F84480000008B4E1883F90F0F8611000000488B064885C00F8430000000E9030000004889F0488B4E104889C2B808000000483BC80F851300000048B85465616D6D6174654839020F845E000000488B73304885F60F843E0000008B4E1883F90F0F8611000000488B064885C00F8426000000E9030000004889F0488B4E10BA04000000483BCA0F820C0000008138636C616E0F84130000009D415B415A415941585F5E5A5958E9DB18F3FF9D415B415A415941585F5E5A5958E9F218F3FF505152565741504151415241539CFC807B20000F85BD000000807B21000F85B3000000488B73384885F60F84480000008B4E1883F90F0F8611000000488B064885C00F8430000000E9030000004889F0488B4E104889C2B808000000483BC80F851300000048B85465616D6D6174654839020F845E000000488B73304885F60F843E0000008B4E1883F90F0F8611000000488B064885C00F8426000000E9030000004889F0488B4E10BA04000000483BCA0F820C0000008138636C616E0F84130000009D415B415A415941585F5E5A5958E9E7CAEFFF9D415B415A415941585F5E5A5958E943CDEFFF'}
  @{N='esp-friend'; K='esp_hook'; O=0x89CF9; A='8B3DC923110090493BDF0F84AA010000'; W='807B2000742A'; H='E95AE60C0090'}
  @{N='aim-friend'; K='aim_hook'; O=0x54FE0; A='1000488B842420010000660F1F440000'; W='807B20000F8579020000'; H='E9523410009090909090'}
)
$nameOff=@(0,11,20,27,32,37,43,49,54,62)
$tableOff=68
$buildLen=51
$startDisp=91
# second copy of the project (the Desktop folder), kept in step; '' = none
$syncDb='C:\Users\user\Desktop\12312-3-main'
if($env:ARMORE3_NOSYNC -eq '1'){ $syncDb='' }
if($syncDb.Length -gt 0){
  if($syncDb.TrimEnd('\','/') -eq $root.TrimEnd('\','/')){ $syncDb='' }
  elseif(-not (Test-Path -LiteralPath (Join-Path $syncDb '123.exe'))){ $syncDb='' }
}

function Hex2Bytes([string]$h){
  $o=New-Object 'byte[]' ($h.Length/2)
  for($i=0;$i -lt $o.Length;$i++){ $o[$i]=[Convert]::ToByte($h.Substring($i*2,2),16) }
  return $o
}
function Get-Sha([byte[]]$d){
  [byte[]]$h=(New-Object Security.Cryptography.SHA256Managed).ComputeHash($d)
  return ([BitConverter]::ToString($h)).Replace('-','')
}
function Find-All([byte[]]$d,[byte[]]$pat){
  $r=New-Object 'System.Collections.Generic.List[int]'
  if($pat.Length -eq 0 -or $d.Length -lt $pat.Length){ return ,$r }
  $n=$d.Length-$pat.Length
  $p0=$pat[0]
  for($i=0;$i -le $n;$i++){
    if($d[$i] -ne $p0){ continue }
    $ok=$true
    for($j=1;$j -lt $pat.Length;$j++){ if($d[$i+$j] -ne $pat[$j]){ $ok=$false; break } }
    if($ok){ [void]$r.Add($i) }
  }
  return ,$r
}
function Match-At([byte[]]$d,[int]$o,[byte[]]$v){
  if($o -lt 0 -or ($o+$v.Length) -gt $d.Length){ return $false }
  for($i=0;$i -lt $v.Length;$i++){ if($d[$o+$i] -ne $v[$i]){ return $false } }
  return $true
}

# file offset -> virtual address (0 when not inside a section)
function Off-To-Va([byte[]]$d,[int]$off){
  $e=[BitConverter]::ToInt32($d,0x3C)
  $nsec=[BitConverter]::ToUInt16($d,$e+6)
  $optsz=[BitConverter]::ToUInt16($d,$e+0x14)
  $ib=[BitConverter]::ToUInt64($d,$e+0x30)
  $s=$e+0x18+$optsz
  for($k=0;$k -lt $nsec;$k++){
    $p=$s+40*$k
    $va=[BitConverter]::ToUInt32($d,$p+12)
    $rsz=[BitConverter]::ToUInt32($d,$p+16)
    $raw=[BitConverter]::ToUInt32($d,$p+20)
    if(($off -ge $raw) -and ($off -lt ($raw+$rsz))){
      return [int64]($ib+$va+($off-$raw))
    }
  }
  return [int64]0
}

# file offset of the Characteristics dword of the section that contains `off`
# (-1 when the offset is not inside a section)
function Section-CharOff([byte[]]$d,[int]$off){
  $e=[BitConverter]::ToInt32($d,0x3C)
  $nsec=[BitConverter]::ToUInt16($d,$e+6)
  $optsz=[BitConverter]::ToUInt16($d,$e+0x14)
  $s=$e+0x18+$optsz
  for($k=0;$k -lt $nsec;$k++){
    $p=$s+40*$k
    $rsz=[BitConverter]::ToUInt32($d,$p+16)
    $raw=[BitConverter]::ToUInt32($d,$p+20)
    if(($rsz -gt 0) -and ($off -ge $raw) -and ($off -lt ($raw+$rsz))){ return $p+36 }
  }
  return -1
}

# find where one site lives in this build; -1 when it is not there
function Resolve-Site([byte[]]$d,$e){
  $A=Hex2Bytes $e.A
  $W=Hex2Bytes $e.W
  $al=$A.Length
  if($al -gt 0){    if((Match-At $d ($e.O-$al) $A) -and (Match-At $d $e.O $W)){ return $e.O }
    $hit=-1; $cnt=0
    foreach($h in (Find-All $d $A)){
      if(Match-At $d ($h+$al) $W){ $hit=$h+$al; $cnt++ }
    }
    if($cnt -eq 1){ return $hit }
    if($cnt -eq 0){ return -1 }
    # several places fit the anchor: take the one closest to the old offset
    $best=-1; $bd=[int]::MaxValue
    foreach($h in (Find-All $d $A)){
      if(-not (Match-At $d ($h+$al) $W)){ continue }
      $o2=$h+$al
      $dist=[Math]::Abs($o2-$e.O)
      if($dist -lt $bd){ $bd=$dist; $best=$o2 }
    }
    return $best
  }
  # no anchor: the site is a zero-filled area located by position only
  for($i=0;$i -lt $W.Length;$i++){ if($d[$e.O+$i] -ne 0){ return -1 } }
  return $e.O
}

function Locate([byte[]]$d){
  $map=@{}; $miss=@(); $moved=@()
  foreach($e in $edits){
    $o=Resolve-Site $d $e
    if($o -lt 0){ $miss+=$e.N; continue }
    $map[$e.N]=$o
    if($o -ne $e.O){ $moved+=($e.N+' '+('{0:+0;-0;0}' -f ($o-$e.O))) }
  }
  return @{ map=$map; miss=$miss; moved=$moved }
}

# the 10-slot accent name table, built for this layout
function Make-Cave([byte[]]$d,[int]$caveOff,[int]$dataOff,[int]$buildOff){
  $caveVa=Off-To-Va $d $caveOff
  $dataVa=Off-To-Va $d $dataOff
  $buildVa=Off-To-Va $d $buildOff
  $c=New-Object 'System.Collections.Generic.List[byte]'
  foreach($b in (Hex2Bytes '488B4530')){ [void]$c.Add($b) }        # mov rax,[rbp+0x30]
  $pos=4
  for($i=0;$i -lt 10;$i++){
    foreach($b in (Hex2Bytes '488D15')){ [void]$c.Add($b) }        # lea rdx,[rip+name]
    $rel=[int](($dataVa+$nameOff[$i])-($caveVa+$pos+7))
    foreach($b in ([BitConverter]::GetBytes($rel))){ [void]$c.Add($b) }
    foreach($b in (Hex2Bytes '488950')){ [void]$c.Add($b) }        # mov [rax+8i],rdx
    [void]$c.Add([byte](8*$i))
    $pos+=11
  }
  foreach($b in (Hex2Bytes '4883C050488945384C89ADA0000000')){ [void]$c.Add($b) }
  $pos+=4+4+7
  foreach($b in (Hex2Bytes 'E9')){ [void]$c.Add($b) }              # jmp back
  $rel=[int](($buildVa+$buildLen)-($caveVa+$pos+5))
  foreach($b in ([BitConverter]::GetBytes($rel))){ [void]$c.Add($b) }
  return $c.ToArray()
}

function Apply([byte[]]$d,$loc){
  $out=New-Object 'byte[]' $d.Length
  [Array]::Copy($d,0,$out,0,$d.Length)
  $caveOff=$loc.map['cave']; $dataOff=$loc.map['data']
  $buildOff=$loc.map['build-site']; $leaOff=$loc.map['table-lea']
  $caveVa=Off-To-Va $out $caveOff
  $dataVa=Off-To-Va $out $dataOff
  $buildVa=Off-To-Va $out $buildOff
  $leaVa=Off-To-Va $out $leaOff
  foreach($e in $edits){
    if(-not $loc.map.ContainsKey($e.N)){ continue }
    $o=$loc.map[$e.N]
    $H=[byte[]](Hex2Bytes $e.H)
    if($e.K -eq 'cave'){
      $code=Make-Cave $out $caveOff $dataOff $buildOff
      $buf=New-Object 'byte[]' $H.Length
      [Array]::Copy($code,0,$buf,0,$code.Length)
      $H=$buf
    }
    elseif($e.K -eq 'build'){
      $rel=[int]($caveVa-($buildVa+5))
      $buf=New-Object 'byte[]' $buildLen
      $buf[0]=0xE9
      [Array]::Copy([BitConverter]::GetBytes($rel),0,$buf,1,4)
      for($k=5;$k -lt $buildLen;$k++){ $buf[$k]=0x90 }
      $H=$buf
    }
    elseif($e.K -eq 'lea'){
      $rel=[int](($dataVa+$tableOff)-($leaVa+7))
      $buf=New-Object 'byte[]' 7
      $buf[0]=0x48; $buf[1]=0x8D; $buf[2]=0x0D
      [Array]::Copy([BitConverter]::GetBytes($rel),0,$buf,3,4)
      $H=$buf
    }
    if(($o+$H.Length) -gt $out.Length){
      $g=New-Object 'byte[]' ($o+$H.Length)
      [Array]::Copy($out,0,$g,0,$out.Length)
      $out=$g
    }
    [Array]::Copy($H,0,$out,$o,$H.Length)
  }
  # the team/clan filter code sits in .rdata, which the compiler marks
  # read-only: the section has to be executable or the first hook taken in a
  # match faults with an execute access violation (0xC0000005, type 8) and the
  # overlay dies right after entering a game.  IMAGE_SCN_MEM_EXECUTE = 0x20000000
  if($loc.map.ContainsKey('friend-code')){
    $co=Section-CharOff $out $loc.map['friend-code']
    if($co -ge 0){
      $ch=[BitConverter]::ToUInt32($out,$co) -bor ([uint32]0x20000000)
      [Array]::Copy([BitConverter]::GetBytes([uint32]$ch),0,$out,$co,4)
    }
  }
  return ,$out
}

# ---------------------------------------------------------------------------
# team / clan filter: the injected code drops a target from ESP and from the
# aim selector when its name starts with "Teammate" (own team) or "clan"
# (the client itself colours clan members by that prefix).  Nothing to
# configure; this is only logged.
# ---------------------------------------------------------------------------

function Test-Patched([byte[]]$d,$loc){
  $bad=@()
  if(-not $loc.map.ContainsKey('watermark')){ $bad+='watermark' }
  elseif(-not (Match-At $d $loc.map['watermark'] ([Text.Encoding]::ASCII.GetBytes('BY armore3')))){ $bad+='watermark' }
  foreach($n in @('end-boot','end-main')){
    if(-not $loc.map.ContainsKey($n)){ $bad+=$n }
    elseif(-not (Match-At $d $loc.map[$n] ([byte[]](0x90,0x90)))){ $bad+=$n }
  }
  if(-not $loc.map.ContainsKey('reserve10')){ $bad+='reserve10' }
  elseif(-not (Match-At $d $loc.map['reserve10'] ([byte[]](0xBA,0x0A,0,0,0)))){ $bad+='reserve10' }
  if(-not $loc.map.ContainsKey('indexbound')){ $bad+='indexbound' }
  elseif(-not (Match-At $d $loc.map['indexbound'] ([byte[]](0x83,0xF9,0x09)))){ $bad+='indexbound' }
  if(-not $loc.map.ContainsKey('data')){ $bad+='data' }
  elseif(-not (Match-At $d $loc.map['data'] ([Text.Encoding]::ASCII.GetBytes('Focus blue')))){ $bad+='data' }
  if(-not $loc.map.ContainsKey('build-site')){ $bad+='build-site' }
  elseif($d[$loc.map['build-site']] -ne 0xE9){ $bad+='build-site' }
  if(-not $loc.map.ContainsKey('cave')){ $bad+='cave' }
  elseif(-not (Match-At $d $loc.map['cave'] ([byte[]](0x48,0x8B,0x45,0x30)))){ $bad+='cave' }
  if(-not $loc.map.ContainsKey('table-lea')){ $bad+='table-lea' }
  elseif(-not (Match-At $d $loc.map['table-lea'] ([byte[]](0x48,0x8D,0x0D)))){ $bad+='table-lea' }
  if(-not $loc.map.ContainsKey('aim-keep')){ $bad+='aim-keep' }
  elseif(-not (Match-At $d $loc.map['aim-keep'] ([byte[]](0xE9,0x7B,0xFF,0xFF,0xFF,0x90)))){ $bad+='aim-keep' }
  if(-not $loc.map.ContainsKey('aim-write-stock')){ $bad+='aim-write-stock' }
  elseif(-not (Match-At $d $loc.map['aim-write-stock'] ([byte[]](0x74,0x13)))){ $bad+='aim-write-stock' }
  if(-not $loc.map.ContainsKey('silent-keep')){ $bad+='silent-keep' }
  elseif(-not (Match-At $d $loc.map['silent-keep'] ([byte[]](0xEB,0x52)))){ $bad+='silent-keep' }
  # NOTE: no check for the removed `aimwalls-visible` site - the client is kept
  # with the stock `aimwalls` read (see gen_anchor_patch.py)
  if(-not $loc.map.ContainsKey('friend-code')){ $bad+='friend-code' }
  elseif(-not (Match-At $d ($loc.map['friend-code']+$startDisp) ([byte[]](0x48,0xB8)))){ $bad+='friend-code' }
  if($loc.map.ContainsKey('friend-code')){
    $co=Section-CharOff $d $loc.map['friend-code']
    if(($co -lt 0) -or (([BitConverter]::ToUInt32($d,$co) -band 0x20000000) -eq 0)){ $bad+='section-exec' }
  }
  if(-not $loc.map.ContainsKey('esp-friend')){ $bad+='esp-friend' }
  elseif($d[$loc.map['esp-friend']] -ne 0xE9){ $bad+='esp-friend' }
  if(-not $loc.map.ContainsKey('aim-friend')){ $bad+='aim-friend' }
  elseif($d[$loc.map['aim-friend']] -ne 0xE9){ $bad+='aim-friend' }
  return $bad
}

# cheap check on a client we have no stock copy of
function Looks-Patched([byte[]]$d){
  $wm=[Text.Encoding]::ASCII.GetBytes('BY armore3')
  $nm=[Text.Encoding]::ASCII.GetBytes('Black'+[char]0+'Gray'+[char]0+'Crimson'+[char]0+'Teal')
  return ((Find-All $d $wm).Count -eq 1) -and ((Find-All $d $nm).Count -eq 1)
}

# ---------------------------------------------------------------------------
# aim assist settings never survive a restart: the client rewrites
# focus_robrun.cfg every time it closes, so anything changed in the menu is
# lost.  Fix-Aim snapshots the aim keys into focus_robrun.aim; every start
# writes that snapshot back over the cfg (Backup-Aim refreshes the file as
# soon as the settings change, so they are saved automatically).
#
# It also guards against values that make aim assist and silent aim flip
# between targets (they look "broken"): an aim cone wider than the screen.
# ---------------------------------------------------------------------------
function Get-CfgFile{ return (Join-Path $env:APPDATA 'focus_robrun.cfg') }
function Get-AimFile{ return (Join-Path $env:APPDATA 'focus_robrun.aim') }

function Read-Kv([string]$path){
  $d=@{}
  foreach($l in (Get-Content -LiteralPath $path)){
    $i=$l.IndexOf('=')
    if($i -gt 0){ $d[$l.Substring(0,$i)]=$l.Substring($i+1) }
  }
  return $d
}

# keys of the aim assist / silent aim / triggerbot settings
$aimKeys=@('aim','aimkey','aimbone','aimteam','aimfov','aimfovvis','aimsmooth','aimrange',
           'aimdelay','aimwall','silent','silentkey','silentfov','silentrange','silentprio',
           'silenthit','silentwall','silentbone','trigger','triggerkey','triggerfov',
           'triggerdelay','triggerhold','triggershot','hitbox','mult','dm')

function Fix-Aim{
  $cfg=Get-CfgFile
  if(-not (Test-Path -LiteralPath $cfg)){ return }
  $aim=Get-AimFile
  $cur=Read-Kv $cfg
  if(-not $cur.ContainsKey('aim')){ return }
  $bak=$cfg+'.before_armore3'
  $snap=@{}                        # keys to write back after this start
  $has=Test-Path -LiteralPath $aim
  if($has){
    $snap=Read-Kv $aim
  } else {
    # first run: the live config is what the player set, keep exactly that
    foreach($k in $aimKeys){ if($cur.ContainsKey($k)){ $snap[$k]=$cur[$k] } }
    if(-not (Test-Path -LiteralPath $bak)){ try{ Copy-Item -LiteralPath $cfg -Destination $bak -Force }catch{} }
    try{ [IO.File]::WriteAllLines($aim,@($aimKeys | Where-Object { $snap.ContainsKey($_) } | ForEach-Object { $_+'='+$snap[$_] })) }catch{}
    Log ('aim: settings saved for the next start ('+$aim+')')
  }
  # what the client gets this run: the saved values, with the absurd ones
  # pulled back into sane limits (those changes are not saved back)
  $force=($env:ARMORE3_AIM -eq '1')
  $want=@{}
  foreach($k in $snap.Keys){ $want[$k]=$snap[$k] }
  $n=0
  if($want.ContainsKey('aimfov') -and ([int]$want['aimfov'] -gt 250)){ $want['aimfov']='160'; $n++ }
  if($want.ContainsKey('silentfov') -and ([int]$want['silentfov'] -gt 200)){ $want['silentfov']='90'; $n++ }
  if($want.ContainsKey('aimrange') -and ([int]$want['aimrange'] -ge 600)){ $want['aimrange']='280'; $n++ }
  if($force){
    if($want.ContainsKey('aimfov')){ $want['aimfov']='160' }
    if($want.ContainsKey('silentfov')){ $want['silentfov']='90' }
    if($want.ContainsKey('aimsmooth')){ $want['aimsmooth']='30' }
    if($want.ContainsKey('aimrange')){ $want['aimrange']='280' }
    if($want.ContainsKey('silentrange')){ $want['silentrange']='300' }
    $n++
  }
  if($n -gt 0){ Log ('aim: '+$n+' value(s) out of range were limited for this run') }
  if($want.Count -eq 0){ return }
  # put the saved settings back into the live config
  $lines=@(Get-Content -LiteralPath $cfg)
  $out=New-Object 'System.Collections.Generic.List[string]'
  $dirty=$false
  foreach($l in $lines){
    $i=$l.IndexOf('=')
    if($i -gt 0){
      $k=$l.Substring(0,$i)
      if($want.ContainsKey($k)){
        if($l.Substring($i+1) -ne $want[$k]){ $dirty=$true }
        $out.Add($k+'='+[string]$want[$k])
        continue
      }
    }
    $out.Add($l)
  }
  if($dirty){
    try{
      [IO.File]::WriteAllLines($cfg,$out)
      Log ('aim: saved aim assist settings restored in '+$cfg)
    } catch { Log ('aim: could not write '+$cfg+': '+$_.Exception.Message) }
  }
}

# while the game runs: remember the aim settings in focus_robrun.aim, so they
# come back on the next start.  The patcher itself exits before the client is
# launched, so the watcher is a separate hidden process; a mutex makes sure
# only one of it runs.
#
# The client reads the config at start and rewrites it on its own schedule,
# so the file can change on its own.  Only edits made while the game is
# running count: the file is remembered as it was when the client came up,
# and written back when it changes.
function Start-Backup-Aim{
  $py=Join-Path $env:TEMP 'focus_aim_keep.ps1'
  $js=@'
$ErrorActionPreference='SilentlyContinue'
$m=New-Object System.Threading.Mutex($false,'focus_aim_keep')
if(-not $m.WaitOne(0)){ exit }
$cfg=Join-Path $env:APPDATA 'focus_robrun.cfg'
$aim=Join-Path $env:APPDATA 'focus_robrun.aim'
$keys=@('aim','aimkey','aimbone','aimteam','aimfov','aimfovvis','aimsmooth','aimrange',
        'aimdelay','aimwall','silent','silentkey','silentfov','silentrange','silentprio',
        'silenthit','silentwall','silentbone','trigger','triggerkey','triggerfov',
        'triggerdelay','triggerhold','triggershot','hitbox','mult','dm')
function Read-Kv([string]$p){
  $d=@{}
  foreach($l in (Get-Content -LiteralPath $p)){
    $i=$l.IndexOf('=')
    if($i -gt 0){ $d[$l.Substring(0,$i)]=$l.Substring($i+1) }
  }
  return $d
}
function Aim-Text($d){
  $o=@()
  foreach($k in $keys){ if($d.ContainsKey($k)){ $o+=$k+'='+$d[$k] } }
  return ($o -join "`r`n")
}
$base=''
$games=0
$quiet=0
$end=(Get-Date).AddHours(8)
while((Get-Date) -lt $end){
  Start-Sleep -Milliseconds 700
  $running=[bool](Get-Process -Name 123 -ErrorAction SilentlyContinue)
  if($running){ $games++; $quiet=0 } else { $quiet++ }
  if(-not (Test-Path -LiteralPath $cfg)){ continue }
  $txt=Aim-Text (Read-Kv $cfg)
  if($txt.Length -eq 0){ continue }
  if($base.Length -eq 0){
    # the client has just read its settings: this is the baseline
    $base=$txt
    continue
  }
  if($txt -eq $base){ continue }
  # the file changed after the client came up (the client writes it by
  # itself right after reading): only a change while the game runs is the
  # player pressing "save" in the menu
  if(-not $running){ continue }
  $old=''
  if(Test-Path -LiteralPath $aim){ $old=[IO.File]::ReadAllText($aim) }
  if($old.Trim() -ne $txt.Trim()){ [IO.File]::WriteAllText($aim,$txt) }
  $base=$txt
  if($running){ $quiet=0 }
  if($games -gt 0 -and (-not $running) -and ($quiet -gt 40)){ break }
}
'@
  try{
    [IO.File]::WriteAllText($py,$js)
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden `
      -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$py) | Out-Null
    Log 'aim: settings watchdog started (saved automatically while you play)'
  } catch { Log ('aim: watchdog failed: '+$_.Exception.Message) }
}

function Save-Record([byte[]]$d,$loc,[string]$sha,[string]$mode){
  try{
    $lines=@('# armore3 build record - written by start.bat, safe to delete',
             ('sha256='+$sha), ('size='+$d.Length), ('mode='+$mode),
             ('time='+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    foreach($e in $edits){
      if($loc.map.ContainsKey($e.N)){
        $lines+=('off.'+$e.N+'=0x'+('{0:X}' -f $loc.map[$e.N])+' shift='+('{0:0;-#;0}' -f ($loc.map[$e.N]-$e.O)))
      }
    }
    [IO.File]::WriteAllLines($buildFile,$lines)
  } catch {}
}

# the shipped launcher starts run\123.exe, keep that copy in sync
function Sync-Run{
  $dst=Join-Path (Join-Path $root 'run') '123.exe'
  if(Test-Path -LiteralPath $dst){
    Sync-File $dst $exe 'run\123.exe updated (that is the copy start.bat launches)'
  }
  if($syncDb){
    Sync-File (Join-Path $syncDb '123.exe') $exe ('copy by the Desktop folder updated: '+$syncDb)
    Sync-File (Join-Path (Join-Path $syncDb 'run') '123.exe') $exe ('run\123.exe in the Desktop folder updated: '+$syncDb)
  }
}

# keep a second copy (the Desktop folder) in step with this one
function Sync-File([string]$dst,[string]$src,[string]$note){
  try{
    $a=[IO.File]::ReadAllBytes($src)
    $same=$false
    if(Test-Path -LiteralPath $dst){
      $b=[IO.File]::ReadAllBytes($dst)
      if($a.Length -eq $b.Length){
        $same=$true
        for($i=0;$i -lt $a.Length;$i++){ if($a[$i] -ne $b[$i]){ $same=$false; break } }
      }
    }
    if($same){ return }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Log $note
  } catch {}
}

try{
  try{ Fix-Aim }catch{ Log ('aim: '+$_.Exception.Message) }
  if(-not (Test-Path -LiteralPath $exe)){ Log 'skip: 123.exe not found'; exit 0 }
  for($pass=0;$pass -lt 2;$pass++){
    $cur=[IO.File]::ReadAllBytes($exe)

    if(Test-Path -LiteralPath $stock){
      $s=[IO.File]::ReadAllBytes($stock)
      $loc=Locate $s
      if($loc.miss.Count -eq 0){
        $patched=Apply $s $loc
        $bad=Test-Patched $patched $loc
        if($bad.Count -gt 0){ Log ('verify failed: '+($bad -join ', ')); exit 1 }
        $newSha=Get-Sha $patched
        $oldSha=Get-Sha $cur
        $mode='patched'
        if($oldSha -eq $newSha){
          Log ('already patched, verified  sha256 '+(Get-Sha $cur).Substring(0,16))
          $mode='fresh'
        } else {
          if(($oldSha -ne (Get-Sha $s)) -and ($cur.Length -eq $s.Length)){
            try{ [IO.File]::WriteAllBytes(($exe+'.bak'),$cur) }catch{}
          }
          [IO.File]::WriteAllBytes($exe,$patched)
          Log ('patched 123.exe  sha256 '+(Get-Sha $patched).Substring(0,16))
        }
        if($loc.moved.Count -gt 0){
          Log ('offsets shifted for this build and were found again: '+($loc.moved -join ', '))
        } else {
          Log 'offsets match the reference build'
        }
        Log 'watermark "BY armore3" | END unload | accent presets 6 -> 10'
        Log 'team and clan members are skipped by ESP and aim automatically'
        Save-Record $s $loc $newSha $mode
        Sync-Run
        try{ Start-Backup-Aim }catch{ Log ('aim: watchdog failed: '+$_.Exception.Message) }
        exit 0
      }
      Log ('NEW BUILD: 123.exe.stock is not a build I know ('+($loc.miss -join ',')+') - left untouched')
      Log 'put the fresh client as 123.exe.stock and run start.bat again'
      exit 2
    }

    if((Looks-Patched $cur) -and ($cur.Length -gt 0x157D80)){
      Log ('already patched, verified  sha256 '+(Get-Sha $cur).Substring(0,16))
      Log 'no 123.exe.stock next to it, so it was not rebuilt (delete 123.exe to force that)'
      Sync-Run
      try{ Start-Backup-Aim }catch{ Log ('aim: watchdog failed: '+$_.Exception.Message) }
      exit 0
    }

    # no stock copy and the target is untouched: try the watermark-only snapshot
    $made=$false
    foreach($cand in @(($exe+'.prewatermark'))){
      if(-not (Test-Path -LiteralPath $cand)){ continue }
      $d=[IO.File]::ReadAllBytes($cand)
      $l2=Locate $d
      if($l2.miss.Count -eq 0){
        [IO.File]::WriteAllBytes($stock,$d)
        Log ('123.exe.stock recreated from '+[IO.Path]::GetFileName($cand))
        $made=$true
        break
      }
    }
    if(-not $made){
      Log 'unknown client build, left untouched'
      exit 0
    }
  }
  Log 'nothing to do'
  exit 0
} catch {
  Log ('error: '+$_.Exception.Message)
  exit 0
}
exit 0
#__ARMORE3_END__
