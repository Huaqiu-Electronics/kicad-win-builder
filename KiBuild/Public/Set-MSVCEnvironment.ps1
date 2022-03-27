function Set-MSVCEnvironment()
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [Arch]$Arch = [Arch]::x64,
        [Parameter()]
        [Arch]$HostArch = [Arch]::x64,
        [string[]]
        [Parameter(ValueFromRemainingArguments=$true)]
        $Arguments
    )

    if($env:VSCMD_VER)
    {
        Write-Host "VS Environment already configured" -ForegroundColor Yellow
        return
    }

    $msvcArch = Get-MSVCArch -Arch $Arch
    $msvcHostArch = Get-MSVCArch -Arch $HostArch

    # prepare the arguments array with the arch info
    $Arguments = @("-arch=$msvcArch") + @("-host_arch=$msvcHostArch") + $Arguments

    $installDir = vswhere -version "[$($settings.VsVersionMin),$($settings.VsVersionMax)]" -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath

    $installDir = $installDir | Select-Object -first 1
    if ($installDir) {
        $path = join-path $installDir 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt'
        if (test-path $path) {
            $version = gc -raw $path
            if ($version) {
                $version = $version.Trim()
                $path = join-path $installDir "Common7\tools\VsDevCmd.bat"
                $argString = $Arguments -join ' '

                Write-Host "Selecting MSVC $version found at $installDir" -ForegroundColor Yellow

                # what is this scary thing?
                # We need to capture the environment variables set by vsdevcmd.bat
                # We use json as an intermediate or else it may get broken by environment variables with spaces in them, json keeps the variables in tact
                $json = $(& "${env:COMSPEC}" /s /c "`"$path`" -no_logo $argString && powershell -Command `"Get-ChildItem env: | Select-Object Key,Value | ConvertTo-Json`"")
                if  (!$?) {
                    Write-Error "Error extracting vsdevcmd.bat environment variables: $LASTEXITCODE"
                } else {
                    $($json | ConvertFrom-Json) | ForEach-Object {
                        $k, $v = $_.Key, $_.Value
                        Set-Content env:\"$k" "$v"
                    }
                }
            }
        }
    }
}