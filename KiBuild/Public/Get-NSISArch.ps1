function Get-NSISArch()
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [Arch]$Arch
    )

    $nsis = ""
    switch ($Arch)
    {
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