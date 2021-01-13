##
# KiCad Powershell Windows Build Assistant
#
#  Usage:
#   Configure/set the vcpkg path
#   ./build.ps1 -Config -VcpkgPath="path to vcpkg"
#
#   Checkout any required tools
#   ./build.ps1 -Init
#   
#   Rebuilds vcpkg dependencies (if updated)
#   ./build.ps1 -Vcpkg
#   
#   Triggers a build
#   ./build.ps1 -Build -Latest
#   
#   Triggers a package operation
#   ./build.ps1 -Package
#
##

param(
    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="config")]
    [Switch]$Config,

    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="init")]
    [Switch]$Init,

    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="build")]
    [Switch]$Build,

    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="vcpkg")]
    [Switch]$Vcpkg,

    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="package")]
    [Switch]$Package,

    [Parameter(Mandatory=$False, ParameterSetName="build")]
    [Switch]$Latest,

    [Parameter(Mandatory=$False, ParameterSetName="build")]
    [Parameter(Mandatory=$False, ParameterSetName="vcpkg")]
    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [ValidateSet('x86', 'x64')]
    [string]$Arch = 'x64',

    [Parameter(Mandatory=$False, ParameterSetName="build")]
    [ValidateSet('Release', 'Debug')]
    [string]$BuildType = 'Release',
	
    [Parameter(Mandatory=$True, ParameterSetName="config")]
	[ValidateScript({Test-Path $_})]
    [string]$VcpkgPath
)

enum Arch {
    x86
    x64
    arm32
    arm64
}

### 
## Base setup
### 

$cmakeDownload = 'https://github.com/Kitware/CMake/releases/download/v3.19.2/cmake-3.19.2-win64-x64.zip'
$cmakeChecksum = "A6FDF509D7A39F1C08B429EAA3EA0012744365A731D00FB770AE88B4D6549FF3"

$vswhereDownload = 'https://github.com/microsoft/vswhere/releases/download/2.8.4/vswhere.exe'
$vswhereChecksum = "E50A14767C27477F634A4C19709D35C27A72F541FB2BA5C3A446C80998A86419"

$swigwinDownload = "https://sourceforge.net/projects/swig/files/swigwin/swigwin-4.0.2/swigwin-4.0.2.zip/download?use_mirror=pilotfiber"
$swigwinChecksum = "DAADB32F19FE818CB9B0015243233FC81584844C11A48436385E87C050346559"

$nsisDownload = "https://sourceforge.net/projects/nsis/files/NSIS%203/3.06.1/nsis-3.06.1.zip/download"
$nsisChecksum = "D463AD11AA191AB5AE64EDB3A439A4A4A7A3E277FCB138254317254F7111FBA7"


$downloadsPathRoot = ($PSScriptRoot+"/.downloads/")
$supportPathRoot = ($PSScriptRoot+"/.support/")

$swigWinPath = ($supportPathRoot+"/swigwin")

# Use TLS1.2 by force in case of older powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$env:Path = $swigWinPath+";"+$env:PATH

### 
# Load and handle Config
###
$settingsPath = $PSScriptRoot + "\settings.json";

$settingDefault = @{
	VcpkgPath = ''
}

$settingsSaved = @{}
if ( Test-Path $settingsPath ) {
    $settingsObj = Get-Content -Path $settingsPath | ConvertFrom-Json

    $settingsObj.psobject.properties | Foreach { $settingsSaved[$_.Name] = $_.Value }
}

$settings = Merge-HashTable -default $settingDefault -uppend $settingsSaved

### 
# Setup aliases to shorten accessing tools
##

function Set-Aliases()
{
    $tmp = Join-Path -Path $settings.VcpkgPath -ChildPath "vcpkg.exe"
    Set-Alias vcpkg $tmp -Option AllScope -Scope Global

    $tmp = Join-Path -Path $PSScriptRoot -ChildPath "tools/7zip/7za.exe"
    Set-Alias 7zip $tmp -Option AllScope -Scope Global
    
    $tmp = Join-Path -Path $supportPathRoot -ChildPath "vswhere.exe"
    Set-Alias vswhere $tmp -Option AllScope -Scope Global
    
    $tmp = Join-Path -Path $supportPathRoot -ChildPath "cmake/bin/cmake.exe"
    Set-Alias cmake $tmp -Option AllScope -Scope Global
    
    $tmp = Join-Path -Path $supportPathRoot -ChildPath "nsis/bin/makensis.exe"
    Set-Alias makensis $tmp -Option AllScope -Scope Global
}

## Invoke it
Set-Aliases

###
# General functions
##

function Get-MSVC-Arch()
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [Arch]$Arch
    )

    $msvc = "amd64"
    switch ($Arch)
    {
        [Arch]::x64   {$msvc = "amd64"}
        [Arch]::x86   {$msvc = "x86"}
        [Arch]::arm32 {$msvc = "arm"}
        [Arch]::arm64 {$msvc = "arm64"}
    }

    return $msvc
}

function Set-VC-Environment()
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

    $msvcArch = Get-MSVC-Arch -Arch $Arch
    $msvcHostArch = Get-MSVC-Arch -Arch $HostArch

    # prepare the arguments array with the arch info
    $Arguments = @("-arch") + $msvcArch + @("-host_arch") + $msvcHostArch + $Arguments

    $installDir = vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($installDir) {
        $path = join-path $installDir 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt'
        if (test-path $path) {
            $version = gc -raw $path
            if ($version) {
                $version = $version.Trim()
                $path = join-path $installDir "Common7\tools\VsDevCmd.bat"
                & $path $Arguments
            }
        }
    }

}

function Get-Absolute-Path($relativePath)
{
  $path = Resolve-Path -Path $relativePath | Select-Object -ExpandProperty Path

  return $path
}

function Reset-Env {
    Set-Item `
        -Path (('Env:', $args[0]) -join '') `
        -Value ((
            [System.Environment]::GetEnvironmentVariable($args[0], "Machine"),
            [System.Environment]::GetEnvironmentVariable($args[0], "User")
        ) -match '.' -join ';')
}

function Reset-Env-Path {
    Reset-Env Path
}

function Build-Kicad {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch,
        [Parameter(Mandatory=$False)]
        [ValidateSet('Release', 'Debug')]
        [string]$buildType = 'Release',
        [Parameter(Mandatory=$False)]
        [bool]$fresh = $False
    )

    $triplet = Get-Vcpkg-Triplet -Arch $arch

    #step down into kicad folder
    Push-Location "$PSScriptRoot\kicad"

    Set-VC-Environment -Arch $arch

    $cmakeBuildFolder = "build/$triplet"

    $generator = "Ninja";

    #delete the old build folder
    if($fresh)
    {
        Remove-Item $cmakeBuildFolder -Recurse -ErrorAction SilentlyContinue
    }

    
    $installPath = "$PSScriptRoot/.out/$triplet/"
    $toolchainPath = ($settings["VcpkgPath"]+"scripts/buildsystems/vcpkg.cmake")

    cmake -G $generator `
        -B $cmakeBuildFolder `
        -S .  `
        -DCMAKE_BUILD_TYPE="$buildType" `
        -DCMAKE_TOOLCHAIN_FILE="$toolchainPath" `
        -DCMAKE_INSTALL_PREFIX="$installPath" `
        -DKICAD_SPICE="ON" `
        -DKICAD_USE_OCE="OFF" `
        -DKICAD_USE_OCC="ON" `
        -DKICAD_SCRIPTING="ON" `
        -DKICAD_SCRIPTING_PYTHON3="ON" `
        -DKICAD_SCRIPTING_WXPYTHON="ON" `
        -DKICAD_SCRIPTING_WXPYTHON_PHOENIX="ON" `
        -DKICAD_SCRIPTING_MODULES="ON" `
        -DKICAD_BUILD_QA_TESTS="OFF" `
        -DKICAD_WIN32_DPI_AWARE="ON"

    if (!$?) {
        Write-Error "Failure generating cmake"
    } else {
        Write-Host "Invoking cmake build" -ForegroundColor Yellow
        cmake --build $cmakeBuildFolder -j 16
        
        if (!$?) {
            Write-Error "Failure with cmake build"
        } else {
            Write-Host "Invoking cmake install" -ForegroundColor Yellow
            cmake --install $cmakeBuildFolder
            
            if (!$?) {
                Write-Error "Failure with cmake install"
            } else {
                Write-Host "Build complete" -ForegroundColor Green
            }
        }
    }

    #restore path
    Pop-Location
}

function Unzip([string] $zip, [string] $dest) {
    $dest = "-o"+$dest;
    7zip x $zip "$dest" -y
}


function Get-Tool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$ToolName,
        [Parameter(Mandatory=$True)]
        [string]$Url,
        [Parameter(Mandatory=$True)]
        [string]$DestPath,
        [Parameter(Mandatory=$True)]
        [string]$DownloadPath,
        [Parameter(Mandatory=$True)]
        [string]$Checksum,
        [Parameter(Mandatory=$False)]
        [bool]$ExtractZip = $False,
        [Parameter(Mandatory=$False)]
        [bool]$ZipRelocate = $False,
        [Parameter(Mandatory=$False)]
        [string]$ZipRelocateFilter = ""
    )
    
    if( -not (Test-Path $DestPath) )
    {
        Write-Host "Downloading $ToolName..." -ForegroundColor Yellow

        Invoke-WebRequest -Uri $Url -OutFile $DownloadPath -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox

        $calculatedChecksum = ( Get-FileHash -Algorithm SHA256 $DownloadPath ).Hash
        if( $calculatedChecksum -ne $Checksum )
        {
            Remove-Item -Path $DownloadPath
            Write-Error "Invalid checksum for $ToolName, expected: $cmakeChecksum actual: $calculatedChecksum"
            Exit 1
        }

        if( $ExtractZip )
        {
            Write-Host "Extracting $ToolName" -ForegroundColor Yellow
            unzip $DownloadPath $supportPathRoot
            if (!$?) {
                Write-Error "Unable to extract $ToolName"
                Exit 2
            }

            if( $ZipRelocate )
            {
                $folders = Get-ChildItem $ZipRelocateFilter -Directory
                Move-Item $folders $DestPath
            }
        }
        else 
        {
            Move-Item $DownloadPath $DestPath
        }
    }
    else
    {
        Write-Host "$ToolName already exists" -ForegroundColor Green
    }
}


function Start-Init {
    # The progress bar slows down download performance by absurd amounts, turn it off
    $ProgressPreference = 'SilentlyContinue'

    Get-Tool -ToolName "CMake" `
             -Url $cmakeDownload `
             -DestPath ($supportPathRoot+'cmake/') `
             -DownloadPath ($downloadsPathRoot+"cmake.zip") `
             -Checksum $cmakeChecksum `
             -ExtractZip $true `
             -ZipRelocate $True `
             -ZipRelocateFilter ($supportPathRoot+'cmake-*/')

    Get-Tool -ToolName "swigwin" `
             -Url $swigwinDownload `
             -DestPath ($supportPathRoot+'swigwin/') `
             -DownloadPath ($downloadsPathRoot+"swigwin.zip") `
             -Checksum $swigwinChecksum `
             -ExtractZip $true `
             -ZipRelocate $True `
             -ZipRelocateFilter ($supportPathRoot+'swigwin-*/')

    Get-Tool -ToolName "nsis" `
             -Url $nsisDownload `
             -DestPath ($supportPathRoot+'nsis/') `
             -DownloadPath ($downloadsPathRoot+"nsis.zip") `
             -Checksum $nsisChecksum `
             -ExtractZip $true `
             -ZipRelocate $True `
             -ZipRelocateFilter ($supportPathRoot+'nsis-*/')

    Get-Tool -ToolName "vswhere" `
             -Url $vswhereDownload `
             -DestPath ($supportPathRoot+'vswhere.exe') `
             -DownloadPath ($downloadsPathRoot+"vswhere.exe") `
             -Checksum $vswhereChecksum `
             -ExtractZip $False

    ### Download Kicad
    if(![System.IO.Directory]::Exists("$PSScriptRoot/kicad/"))
    {
        Write-Host "Cloning kicad repo";
        git clone https://gitlab.com/kicad/code/kicad.git kicad
    }

    # Restore progress bar
    $ProgressPreference = 'Continue'
}

function Get-Vcpkg-Triplet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch
    )

    $triplet = "$arch-windows"
    return $triplet;
}


function Build-Vcpkg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch
    )

    # Bootstrap vcpkg
    Push-Location $settings["VcpkgPath"]
    .\bootstrap-vcpkg.bat

    # Setup dependencies
    $triplet = Get-Vcpkg-Triplet -Arch $arch
    $dependencies = @( "boost",
                        "cairo",
                        "curl", 
                        "glew",
                        "gettext",
                        "glm",
                        "icu",
                        "ngspice",
                        "opencascade",
                        "opengl",
                        "openssl",
                        "python3",
                        "wxwidgets",
                        "wxpython",
                        "zlib")

    # Format the dependencies with the triplet
    for ($i = 0; $i -lt $dependencies.Count; $i++) {
        $dependencies[$i] = $dependencies[$i]+":$triplet"
    }
    vcpkg install $dependencies
    
    if (!$?) {
        Write-Error "Failure installing vcpkg ports"
    } else {
        Write-Host "vcpkg ports installed/updated" -ForegroundColor Green
    }

    Pop-Location
}

function Merge-HashTable {
    param(
        [hashtable] $default,
        [hashtable] $uppend
    )

    # Clone for idempotence
    $defaultClone = $default.Clone();

    # Remove keys that exist in both uppend and default from default
    foreach ($key in $uppend.Keys) {
        if ($defaultClone.ContainsKey($key)) {
            $defaultClone.Remove($key);
        }
    }

    # Union both sets
    return $defaultClone + $uppend;
}

function Start-Package {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch
    )

    $triplet = Get-Vcpkg-Triplet -Arch $arch

    $vcpkgInstalledRoot = Join-Path -Path $settings["VcpkgPath"] -ChildPath "installed\$triplet\"
    $destRoot = Join-Path -Path $PSScriptRoot -ChildPath ".out\$triplet\"

    $vcpkgBinCopy = @( "boost*",
                        "TK*",
                        "wx*",
                        "jpeg62*",
                        "libpng16*",
                        "tiff*",
                        "zlib*",
                        "libcurl*",
                        "python*",
                        "glew32*",
                        "cairo*",
                        "libexpat*",
                        "lzma*",
                        "fontconfig*",
                        "freetype*",
                        "bz2*",
                        "brotli*",
                        "charset*",
                        "libwebpmux*",
                        "libcrypto*",
                        "libssl*",
                        "libffi*",
                        "ngspice*",
                        "pthread*",
                        "turbojpeg*",
                        "zstd*",
                        "sqlite*",
                        "icu*",
                        "iconv*",
                        "intl*"
                    )

                        
    $vcpkgInstalledBin = Join-Path -Path $vcpkgInstalledRoot -ChildPath "bin\"
    $destBin = Join-Path -Path $destRoot -ChildPath "bin\"

    Write-Host "Copying from $vcpkgInstalledBin to $destBin" -ForegroundColor Yellow
    foreach( $copyFilter in $vcpkgBinCopy ) 
    {
        $source = "$vcpkgInstalledBin\$copyFilter"
        
        Write-Host "Copying $source" -ForegroundColor Green
        Copy-Item $source -Destination $destBin -Recurse
    }

    ## now python3
    $python3Source = "$vcpkgInstalledRoot\tools\python3\"
    $python3Dest = "$destRoot\lib\"
    Write-Host "Copying python3 $python3Source to $python3Dest" -ForegroundColor Yellow
    Copy-Item $python3Source -Destination $python3Dest -Recurse -Container  -Force

    ## now nsis
    $nsisSource = Join-Path -Path $PSScriptRoot -ChildPath "nsis\"
    Write-Host "Copying nsis $nsisSource to $nsisDest" -ForegroundColor Yellow
    Copy-Item $nsisSource -Destination $destRoot -Recurse -Container -Force

    ## Run NSIS
    $nsisScript = Join-Path -Path $destRoot -ChildPath "nsis\install.nsi"
    $packageVersion = ""
    $kicadVersion = ""

    Write-Host "Copying LICENSE.README as copyright.txt" -ForegroundColor Yellow
    Copy-Item "$PSScriptRoot/kicad/LICENSE.README" -Destination "$destRoot\COPYRIGHT.txt" -Force

    makensis /DPACKAGE_VERSION=$packageVersion `
        /DKICAD_VERSION=$kicadVersion `
        /DOUTFILE="..\kicad-$packageVersion-$arch.exe" `
        /DARCH="$arch" `
        "$nsisScript"

}


function Set-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$VcpkgPath
    )

    $settings.VcpkgPath = $VcpkgPath

    $settings | ConvertTo-Json -Compress | Set-Content -Path $settingsPath
}

function Get-Latest-Kicad {
    Push-Location "$PSScriptRoot/kicad"
    git reset --hard origin/master
    git clean -f
    git pull --rebase
    Pop-Location
}

###
# Decode and execute the selected script stage
###

if( $Config )
{
    Set-Config -VcpkgPath $VcpkgPath
}

if( $Init )
{
    Start-Init
}

if( $Vcpkg )
{
    Build-Vcpkg -arch $Arch
}

if( $Latest )
{
    Get-Latest-Kicad
}

if( $Build )
{
    Build-KiCad -arch $Arch -buildType $BuildType
}

if( $Package )
{
    Start-Package -arch $Arch
}