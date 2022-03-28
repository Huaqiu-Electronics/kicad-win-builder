function Get-MSVCArch() {
    <#
    .SYNOPSIS
        Returns the MSVC architecture string for a given Arch enum value
    .DESCRIPTION
        The cmdlet takes an Arch enum value and returns the matching MSVC
        arch string that is used in invocations of MSVC tools and accessing
        file paths.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [Arch]$Arch
    )

    $msvc = "amd64"
    switch ($Arch) {
        ([Arch]::x64) {
            $msvc = "amd64"
            break
        }
        ([Arch]::x86) {
            $msvc = "x86"
            break
        }
        ([Arch]::arm) {
            $msvc = "arm"
            break
        }
        ([Arch]::arm64) {
            $msvc = "arm64"
            break
        }
    }

    return $msvc
}