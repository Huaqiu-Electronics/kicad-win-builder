# path.ps1 - KiCad Huaqiu installer PATH helper
#
# Idempotent, entry-preserving Add/Remove of one directory on the Windows
# PATH. Invoked by the NSIS installer/uninstaller via nsExec: the machine or
# user PATH routinely exceeds NSIS's 1024-character string buffer, which makes
# a ReadRegStr/WriteRegExpandStr round-trip inside NSIS corrupt (or wipe) the
# value. This script performs the same read-modify-write through the registry
# API, which has no such limit, and preserves the original value kind
# (REG_EXPAND_SZ stays REG_EXPAND_SZ, %VAR% references stay unexpanded).

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Add", "Remove")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$Dir,

    [ValidateSet("HKLM", "HKCU")]
    [string]$Scope = "HKCU",

    # Test-only override of the registry subkey (default derived from Scope).
    [string]$RegistryPath = ""
)

$ErrorActionPreference = "Stop"

if ($RegistryPath -eq "") {
    if ($Scope -eq "HKLM") {
        $RegistryPath = "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
    } else {
        $RegistryPath = "Environment"
    }
}

$baseKey = if ($Scope -eq "HKLM") {
    [Microsoft.Win32.Registry]::LocalMachine
} else {
    [Microsoft.Win32.Registry]::CurrentUser
}

try {
    $key = $baseKey.OpenSubKey($RegistryPath, $true)
} catch {
    [Console]::Error.WriteLine("path.ps1: cannot open registry key $Scope\$RegistryPath : $_")
    exit 1
}
if ($null -eq $key) {
    [Console]::Error.WriteLine("path.ps1: registry key not found: $Scope\$RegistryPath")
    exit 1
}

# Read the raw value (REG_EXPAND_SZ left unexpanded) and its value kind.
$path = $null
$kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
try {
    if ($key.GetValueNames() -contains "Path") {
        $path = $key.GetValue("Path", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = $key.GetValueKind("Path")
    }
} catch {
    [Console]::Error.WriteLine("path.ps1: cannot read Path value: $_")
    $key.Close()
    exit 1
}

$dir = [string]$Dir
if ($dir -eq "") {
    [Console]::Error.WriteLine("path.ps1: -Dir must not be empty")
    $key.Close()
    exit 1
}

# Normalize into entries, keeping each entry's original text untouched.
$entries = @()
if ($null -ne $path -and "$path" -ne "") {
    $entries = @($path -split ';' | Where-Object { $_ -ne '' })
}

# Preserve the existing value kind; a freshly created value uses the standard
# REG_EXPAND_SZ so future %VAR% entries behave like the rest of the system.
$writeKind = if ($kind -eq [Microsoft.Win32.RegistryValueKind]::ExpandString) {
    [Microsoft.Win32.RegistryValueKind]::ExpandString
} else {
    [Microsoft.Win32.RegistryValueKind]::String
}

try {
    if ($Action -eq "Add") {
        $exists = $entries | Where-Object { $_ -ieq $dir }
        if (-not $exists) {
            $newValue = if ($entries.Count -gt 0) { ($entries -join ';') + ';' + $dir } else { $dir }
            $key.SetValue("Path", $newValue, $writeKind)
        }
    } else {
        $remaining = @($entries | Where-Object { $_ -ine $dir })
        if ($remaining.Count -eq 0) {
            if ($key.GetValueNames() -contains "Path") {
                $key.DeleteValue("Path", $false)
            }
        } else {
            $newValue = $remaining -join ';'
            $key.SetValue("Path", $newValue, $writeKind)
        }
    }
} catch {
    [Console]::Error.WriteLine("path.ps1: $Action failed for '$dir': $_")
    $key.Close()
    exit 1
}

$key.Close()
exit 0
