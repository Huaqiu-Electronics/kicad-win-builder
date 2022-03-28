function Get-NSISArch() {    
    <#
    .SYNOPSIS
        Returns the packaging arch string for a given Arch enum value
    .DESCRIPTION
        The cmdlet takes an Arch enum value and returns the a string
        used in packaging KiCad applications
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [Arch]$Arch
    )

    $nsis = ""
    switch ($Arch) {
        ([Arch]::x64) {
            $nsis = "x86_64"
            break
        }
        ([Arch]::x86) {
            $nsis = "i686"
            break
        }
        ([Arch]::arm) {
            $nsis = "arm"
            break
        }
        ([Arch]::arm64) {
            $nsis = "arm64"
            break
        }
    }

    return $nsis
}