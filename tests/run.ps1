# Runs Scion's regression tests (tests/cases.txt) on Windows, from out\tests (built on Linux by tests/build.sh).
# Usage:  powershell -ExecutionPolicy Bypass -File tests\run.ps1 [filter]
# SCION_SKIP: a regular expression of test names to skip, as in tests/run.sh (e.g. $env:SCION_SKIP = 'Metal|MSL').
param([string]$Filter = '')
$root = Split-Path -Parent $PSScriptRoot
$scion = if ($env:SCION) { $env:SCION } else { Join-Path $root 'bin\scion.exe' }
$tests = Join-Path $root 'out\tests'
if (-not (Test-Path $tests)) { Write-Host 'out\tests is missing: build the tests first (tests/build.sh)'; exit 1 }
Set-Location $tests
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # scion writes UTF-8
$pass = 0; $fail = 0; $skip = 0

function Run-Case([string]$name, [string]$want, [string]$envs, [string]$argline) {
    if ($env:SCION_SKIP -and $name -match $env:SCION_SKIP) { $script:skip++; return }
    $argv = @([regex]::Matches($argline, '"[^"]*"|\S+') | ForEach-Object { $_.Value.Trim('"') })
    foreach ($a in $argv) { if ($a -like 'apps/*' -and -not (Test-Path $a)) { $script:skip++; return } }
    $p = $argv[0]
    if ($p -notin 'install', 'uninstall') {
        if ($p -like '*.app') { if (-not (Test-Path "$p/Contents/MacOS")) { $script:skip++; return } }
        elseif (-not (Test-Path $p)) { $script:skip++; return }
    }
    $vars = @(); if ($envs -ne '-') { $vars = $envs -split ' ' }
    foreach ($v in $vars) { $k, $x = $v -split '=', 2; [Environment]::SetEnvironmentVariable($k, $x) }
    $out = & $scion @argv 2>&1 | Out-String
    foreach ($v in $vars) { [Environment]::SetEnvironmentVariable(($v -split '=', 2)[0], $null) }
    if ($out.Contains($want)) { Write-Host "OK   $name" -ForegroundColor Green; $script:pass++ }
    else {
        Write-Host "FAIL $name" -ForegroundColor Red
        ($out.TrimEnd() -split "`n" | Select-Object -Last 5) | ForEach-Object { Write-Host "     $_" }
        $script:fail++
    }
}

foreach ($line in Get-Content (Join-Path $root 'tests\cases.txt')) {
    if ($line -match '^\s*(#|$)') { continue }
    $name, $want, $envs, $argline = $line -split '\|', 4 | ForEach-Object { $_.Trim() }
    if ($Filter -and -not $name.Contains($Filter)) { continue }
    if ("$name$envs$argline".Contains('{arch}')) {
        foreach ($a in 'x86_64', 'arm64') { Run-Case $name.Replace('{arch}', $a) $want $envs.Replace('{arch}', $a) $argline.Replace('{arch}', $a) }
    } else { Run-Case $name $want $envs $argline }
}
Write-Host "passed: $pass, failed: $fail, skipped: $skip"
exit $fail
