function Get-HostArch() {    
    <#
    .SYNOPSIS
        Returns the current host arch as an Arch enum value
    #>

    $arch = [Arch]::x64
    $hostArchStr = $Env:PROCESSOR_ARCHITECTURE.ToLower()
    switch -Exact ($hostArchStr) {
        'amd64' {
            $arch = [Arch]::x64
            break
        }
        'x86' {
            $arch = [Arch]::x86
            break
        }
        'arm' {
            $arch = [Arch]::arm
            break
        }
        'arm64' {
            $arch = [Arch]::arm64
            break
        }
    }

    return $arch
}