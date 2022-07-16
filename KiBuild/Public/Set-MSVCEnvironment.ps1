function Set-MSVCEnvironment() {
    <#
    .SYNOPSIS
        Setups powershell environment variables with a MSVC enviroment 
    .DESCRIPTION
        The cmdlet utilizes vswhere to locate a MSVC environment and 
        then executes VsDevCmd.bat to extract all environment variables set
        so we can reproduce them in the powershell environment.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [Arch]$Arch = [Arch]::x64,
        [Parameter()]
        [Arch]$HostArch = [Arch]::x64,
        [Parameter(Mandatory=$False)]
        [string]$VersionMin = '',
        [Parameter(Mandatory=$False)]
        [string]$VersionMax = '',
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

    $installDir = vswhere -version "[$VersionMin,$VersionMax]" -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath

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
                $json = $(& "${env:COMSPEC}" /s /c "`"$path`" -no_logo $argString >NUL && powershell -Command `"Get-ChildItem env: | Select-Object Key,Value | ConvertTo-Json`"")
                if  (!$?) {
                    Write-Error "Error extracting vsdevcmd.bat environment variables: $LASTEXITCODE"
                } else {
                    try {
                        $($json | ConvertFrom-Json) | ForEach-Object {
                            $k, $v = $_.Key, $_.Value
                            Set-Content env:\"$k" "$v"
                        }
                    } catch {
                        Write-Error -Message "Error converting json $json" -TargetObject $json -ErrorAction Stop
                    }
                }
            }
        }
    } else {
        Write-Error -Message "Could not find MSVC Environment" -Exception ([System.IO.FileNotFoundException]::new()) -ErrorAction Stop
    }

    
    if( -not (Test-Path alias:cmake ) )
    {
        $cmakePath = Join-Path -Path $env:VCIDEInstallDir -ChildPath "\..\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" -Resolve
        $ninjaFolder = Join-Path -Path $env:VCIDEInstallDir -ChildPath "\..\CommonExtensions\Microsoft\CMake\Ninja\" -Resolve
        $ninjaPath = Join-Path -Path $ninjaFolder -ChildPath "ninja.exe" -Resolve

        if( -not (Test-Path $cmakePath) )
        {
            Write-Error "Failed finding cmake.exe at $cmakePath, is MSVC installed with CMake support?"
            Exit [ExitCodes]::CmakeLocation
        }

        Set-Alias cmake $cmakePath -Option AllScope -Scope Global
        Set-Alias ninja $ninjaPath -Option AllScope -Scope Global

        $env:NINJA_PATH = $ninjaPath
        $env:Path = $ninjaFolder+";"+$env:Path;
    }
}