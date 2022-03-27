function Get-MSVCArch()
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [Arch]$Arch
    )

    $msvc = "amd64"
    switch ($Arch)
    {
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