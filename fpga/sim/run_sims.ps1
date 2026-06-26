# fpga/sim/run_sims.ps1 — compile & run module testbenches in Vivado xsim.
$ErrorActionPreference = "Stop"
function Get-VivadoBin {
    if ($env:VIVADO_BIN) { return $env:VIVADO_BIN.TrimEnd('\') }
    $cmd = Get-Command vivado -ErrorAction SilentlyContinue
    if ($cmd) { return (Split-Path $cmd.Source -Parent) }
    throw "Vivado not found. Set VIVADO_BIN or add vivado to PATH."
}
$vivado = Get-VivadoBin
$root   = Split-Path $PSScriptRoot -Parent          # fpga/
$rtl    = Join-Path $root "rtl"
$sim    = $PSScriptRoot
$data   = Join-Path $root "data"

$work = Join-Path $env:TEMP "rf_adda_sim"
Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item (Join-Path $data "boot_rom.mem") $work -ErrorAction SilentlyContinue
Set-Location $work

$suite = [ordered]@{
  "tb_uart_cmd_parser" = @(
    "rf_uart\uart_rx.v","rf_uart\uart_tx.v","rf_uart\uart_tx_byte.v","rf_uart\uart_cmd_parser.v"
  )
  "tb_boot_fsm" = @("rf_ctrl_path\boot_fsm.v","rf_ctrl_path\boot_rom.v")
}

$results = [ordered]@{}
foreach ($tb in $suite.Keys) {
    Write-Host "==================== $tb ====================" -ForegroundColor Cyan
    $lines = @("-i $rtl")
    $lines += (Join-Path $sim "$tb.v")
    foreach ($s in $suite[$tb]) { $lines += (Join-Path $rtl $s) }
    ($lines -replace '\\','/') -join "`n" | Set-Content "$tb.f" -Encoding ASCII

    & "$vivado\xvlog.bat" -f "$tb.f" 2>&1 | Select-String "ERROR" | ForEach-Object { Write-Host $_ }
    & "$vivado\xelab.bat" $tb -s "${tb}_snap" 2>&1 | Select-String "ERROR" | ForEach-Object { Write-Host $_ }
    $out = & "$vivado\xsim.bat" "${tb}_snap" -R 2>&1
    $out | Select-String -Pattern "PASS|FAIL|failures" | ForEach-Object { Write-Host $_ }
    if ($out -match "PASS") { $results[$tb] = "PASS" }
    else { $results[$tb] = "FAIL" }
}

Write-Host "`n==================== SUMMARY ====================" -ForegroundColor Yellow
$nfail = 0
foreach ($tb in $results.Keys) {
    $st = $results[$tb]
    $col = if ($st -eq "PASS") { "Green" } else { "Red" }
    Write-Host ("{0,-26} {1}" -f $tb, $st) -ForegroundColor $col
    if ($st -ne "PASS") { $nfail++ }
}
Write-Host ("`n{0}/{1} testbenches passed" -f ($results.Count-$nfail), $results.Count)
Set-Location $root
exit $nfail
