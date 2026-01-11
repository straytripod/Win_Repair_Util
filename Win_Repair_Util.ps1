<#
.SYNOPSIS
Advanced Windows DISM + SFC Repair Utility

Supports:
- Windows 10 / 11
- Windows Server 2016 / 2019 / 2022 / 2025

.DESCRIPTION
- Repairs the currently running Windows installation
- Uses DISM /online correctly (local OS image, not the internet)
- Attempts local install media if needed
- Provides guided Microsoft ISO download instructions when sources are missing
- Produces a technician-ready task report for ticketing
#>

#region Global Setup
$LogRoot = "$env:SystemRoot\Logs\WindowsRepair"
$TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = "$LogRoot\Repair-$TimeStamp.log"
$ReportFile = "$LogRoot\TaskReport-$TimeStamp.txt"

New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null

function Write-Log {
    param ($Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}
#endregion

#region OS Detection
function Get-RunningOSInfo {
    $os = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    
    $productName = $os.ProductName
    $build = [int]$os.CurrentBuild

    # Server OS correction (more robust)
    if ($productName -like "*Server*") {
        if ($build -ge 26100) { $productName = "Windows Server 2025" }
        elseif ($build -ge 20348) { $productName = "Windows Server 2022" }
        elseif ($build -ge 17763) { $productName = "Windows Server 2019" }
        elseif ($build -ge 14393) { $productName = "Windows Server 2016" }
    }
    # Client OS correction
    elseif ($build -ge 22000 -and $productName -like "*Windows 10*") {
        $productName = $productName.Replace("10", "11")
    }

    [PSCustomObject]@{
        ProductName = $productName
        Edition     = $os.EditionID
        Build       = $os.CurrentBuild
        UBR         = $os.UBR
        FullBuild   = "$($os.CurrentBuild).$($os.UBR)"
    }
}
#endregion

#region Reboot Detection
function Test-RebootPending {
    return (
        (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") -or
        (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")
    )
}

#endregion

#region Local Media Detection
function Find-LocalInstallMedia {
    $searchPaths = @("C:\ISO","C:\InstallMedia","D:\ISO")
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $iso = Get-ChildItem $path -Filter *.iso -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($iso) { return $iso.FullName }
        }
    }
    return $null
}
#endregion

#region DISM Error Interpretation
function Explain-DismError {
    param ($Output)

    if ($Output -match "0x800f081f") {
        return "0x800f081f - Source files could not be found. Matching install media is required."
    }
    if ($Output -match "0x800f0906") {
        return "0x800f0906 - Windows Update or repair source unavailable."
    }
    if ($Output -match "source files could not be found") {
        return "DISM could not locate component store repair files."
    }
    return "A known DISM failure was NOT detected. Review DISM.log for details."
}
#endregion

#region Microsoft ISO Guidance (Edition + Version Aware)
function Show-MicrosoftISOGuidance {
    param ($OSInfo)

    Write-Host "`nDISM requires matching Windows install media." -ForegroundColor Yellow
    Write-Host "`nDetected OS:" -ForegroundColor Cyan
    Write-Host " - Product : $($OSInfo.ProductName)"
    Write-Host " - Edition : $($OSInfo.Edition)"
    Write-Host " - Build   : $($OSInfo.FullBuild)"

    Write-Host "`nWhat DISM needs:" -ForegroundColor Cyan
    Write-Host " - Same OS major version"
    Write-Host " - Same edition (Standard, Datacenter, Pro, etc.)"
    Write-Host " - Same language"
    Write-Host " - Build must be >= installed build"

    Write-Host "`nOfficial Microsoft download location:" -ForegroundColor Cyan

    $url = switch -Wildcard ($OSInfo.ProductName) {
        "*Windows 10*"     { "https://www.microsoft.com/software-download/windows10" }
        "*Windows 11*"     { "https://www.microsoft.com/software-download/windows11" }
        "*Server 2016*"    { "https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2016" }
        "*Server 2019*"    { "https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019" }
        "*Server 2022*"    { "https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022" }
        "*Server 2025*"    { "https://www.microsoft.com/windows-server" }
        default            { "https://www.microsoft.com/software-download" }
    }

    Write-Host " - $url"
    Write-Host "`nDownload the ISO, place it in C:\ISO, then rerun Option 2." -ForegroundColor DarkGray
    Write-Host "`nThe download links are hard coded in this script and may not the referance current location." -ForegroundColor red

    try { Start-Process $url } catch {}
    return $url
}
#endregion

#region Command Execution
function Invoke-And-Capture {
    param ($Command)
    Write-Log "Running: $Command"
    $output = Invoke-Expression $Command 2>&1
    $output | Tee-Object -Append $LogFile
    return $output
}
#endregion

#region Repair Logic
function Run-Repair {
    param ($Source)

    Invoke-And-Capture "dism /online /cleanup-image /checkhealth"
    Invoke-And-Capture "dism /online /cleanup-image /scanhealth"

    $cmd = "dism /online /cleanup-image /restorehealth"
    if ($Source) { $cmd += " /source:$Source /limitaccess" }

    $dismOutput = Invoke-And-Capture $cmd
    $sfcOutput  = Invoke-And-Capture "sfc /scannow"

    $errorExplanation = Explain-DismError ($dismOutput -join "`n")

    [PSCustomObject]@{
        DismOutput = $dismOutput
        SfcOutput  = $sfcOutput
        ErrorText  = $errorExplanation
    }
}
#endregion

#region Report
function Write-TaskReport {
    param ($OS,$Result,$Source,$Reboot,$GuidanceURL)

@"
Windows Repair Task Report
=========================

System:
- OS       : $($OS.ProductName)
- Edition  : $($OS.Edition)
- Build    : $($OS.FullBuild)

Actions:
- DISM CheckHealth
- DISM ScanHealth
- DISM RestoreHealth
- SFC Scannow

Repair Source:
- $Source

DISM Result:
- $($Result.ErrorText)

Reboot Required:
- $Reboot

Guidance Provided:
- $GuidanceURL

Logs:
- $LogFile

Notes:
- DISM /online targets the currently running OS image
- DISM does NOT automatically use the internet
- Matching install media resolves most repair failures
=========================
"@ | Set-Content $ReportFile

Write-Host "Task report saved to $ReportFile" -ForegroundColor Green
}
#endregion

#region Main
$OSInfo = Get-RunningOSInfo
Write-Log "Detected OS: $($OSInfo.ProductName) $($OSInfo.FullBuild)"

Write-Host "`nWindows DISM + SFC Repair Utility" -ForegroundColor Cyan
Write-Host "1) Repair using current OS component store"
Write-Host "2) Repair using local install media"
Write-Host "Q) Quit"

$choice = Read-Host "Select option"

$guidance = ""
$sourceUsed = "None"

switch ($choice) {
    "1" {
        $result = Run-Repair
    }
    "2" {
        $iso = Find-LocalInstallMedia
        if (-not $iso) {
            $guidance = Show-MicrosoftISOGuidance $OSInfo
            Write-TaskReport $OSInfo ([PSCustomObject]@{ErrorText="No install media found"}) "None" (Test-RebootPending) $guidance
            exit
        }
        $guidance = "Local ISO used: $iso"
        $result = Run-Repair
        $sourceUsed = $iso
    }
    default { exit }
}

$reboot = Test-RebootPending
Write-TaskReport $OSInfo $result $sourceUsed $reboot $guidance
#endregion
