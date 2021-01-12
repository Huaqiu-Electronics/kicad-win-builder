##
# KiCad Powershell Windows Build Assistant
#
#  Usage:
#   Configure/set the vcpkg path
#   ./build.ps1 -Config -VcpkgPath="path to vcpkg"
#
#   Checkout any required tools
#   ./build.ps1 -Setup
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

enum Arches {
    x86
    x64
}

param(
    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="config")]
    [Switch]$Config,

    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="setup")]
    [Switch]$Setup,

    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="build")]
    [Switch]$Build,
	
    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="vcpkg")]
    [Switch]$Vcpkg,

    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="package")]
    [Switch]$Package,

    [Parameter(Mandatory=$False, ParameterSetName="build")]
    [Switch]$Latest,

    [Parameter(Mandatory=$True, ParameterSetName="build")]
    [Parameter(Mandatory=$True, ParameterSetName="vcpkg")]
    [ValidateNotNullOrEmpty()]
    [Arches]$Arch,

    [Parameter(Mandatory=$True, ParameterSetName="build")]
    [ValidateSet('Release', 'Debug')]
    [string]$BuildType = 'Release',
	
    [Parameter(Mandatory=$True, ParameterSetName="config")]
	[ValidateScript({Test-Path $_})]
    [string]$VcpkgPath
)

### 
## Base setup
### 

$cmakeDownload = 'https://github.com/Kitware/CMake/releases/download/v3.19.2/cmake-3.19.2-win64-x64.zip';
$vswhereDownload = 'https://github.com/microsoft/vswhere/releases/download/2.8.4/vswhere.exe'

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
$vcpkgPath = Join-Path -Path $settings.VcpkgPath -ChildPath "vcpkg.exe"

Set-Alias vcpkg $vcpkgPath -Option AllScope
Set-Alias 7zip ./tools/7zip/7za.exe -Option AllScope
Set-Alias vswhere $supportPathRoot+"vswhere.exe" -Option AllScope

function Find-VS()
{
    [CmdletBinding()]
    param (
        [Parameter()]
        $Arch = 'x64',
        [Parameter()]
        $HostArch = 'x64',
        [Parameter(ValueFromRemainingArguments=$true)]
        $Arguments
    )

    $installDir = vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($installDir) {
        $path = join-path $installDir 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt'
        if (test-path $path) {
            $version = gc -raw $path
            if ($version) {
                $version = $version.Trim()
                $path = join-path $installDir "VC\Tools\MSVC\$version\bin\Host$HostArch\$Arch\cl.exe"
                & $path $Arguments
            }
        }
    }
}

function Set-VC-Vars($vcvarsname)
{
    Push-Location "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build"
    cmd /c "$vcvarsname.bat&set" |
    Foreach-Object {
      if ($_ -match "=") {
        $v = $_.split("="); set-item -force -path "ENV:\$($v[0])"  -value "$($v[1])"
      }
    }
    Pop-Location
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
        [ValidateSet('x86', 'x64')]
        [string]$arch,
        [Parameter(Mandatory=$False)]
        [ValidateSet('Release', 'Debug')]
        [string]$buildType = 'Release'
    )

    $cmakeBin = Get-Absolute-Path(".\tools\cmake\bin\")
    Set-Alias cmake $cmakeBin/cmake.exe

    Reset-Env-Path
    $vcpkgBase = Get-Absolute-Path("./vcpkg")

    #step down into kicad folder
    Push-Location kicad

    $generator = "Ninja";
    if($arch -eq "x64")
    {
        $cmakeBuildFolder = "build64";
        Set-VC-Vars("vcvars64")
    }
    elseif($arch -eq "x86")
    {
        $cmakeBuildFolder = "build32";
        Set-VC-Vars("vcvars32")
    }
    #delete the old build folder
    Remove-Item $cmakeBuildFolder -Recurse


    cmake -G $generator `
        -B $cmakeBuildFolder `
        -S .  `
        -DCMAKE_BUILD_TYPE="$buildType" `
        -DCMAKE_TOOLCHAIN_FILE="$vcpkgBase/scripts/buildsystems/vcpkg.cmake" `
        -DKICAD_SPICE="ON" `
        -DKICAD_USE_OCE="OFF" `
        -DKICAD_SCRIPTING="OFF" `
        -DKICAD_SCRIPTING_WXPYTHON="OFF" `
        -DKICAD_SCRIPTING_MODULES="ON"

    if (!$?) {
        Write-Error "Failure generating cmake"
    } else {
        Write-Host "Invoking cmake build"
        cmake --build $cmakeBuildFolder -j 16
    }

    #restore path
    Pop-Location
}

function Unzip([string] $zip, [string] $dest) {
    $dest = "-o"+$dest;
    7zip x $zip "$dest" -y
}


function Start-Setup {
    # The progress bar slows down download performance by absurd amounts, turn it off
    $ProgressPreference = 'SilentlyContinue'

    if(![System.IO.Directory]::Exists( $supportPathRoot+"cmake" ))
    {
        Write-Host "Downloading CMake..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $cmakeDownload -OutFile ($downloadsPathRoot+"cmake.zip")
        Write-Host "Extracting Cmake" -ForegroundColor Yellow
        unzip ($downloadsPathRoot+"cmake.zip") $supportPathRoot

        $folder = Get-ChildItem ($supportPathRoot+'cmake-*/') -Directory
        Move-Item $folder ($supportPathRoot+'cmake/')
    }
    else
    {
        Write-Host "Cmake already exists";
    }

    if(![System.IO.File]::Exists( $supportPathRoot+"vswhere.exe" ))
    {
        Write-Host "Downloading Vswhere..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $vswhereDownload -OutFile ($supportPathRoot+"vswhere.exe")
    }
    else
    {
        Write-Host "vswhere already exists";
    }

    $swigwinDownload = "https://sourceforge.net/projects/swig/files/swigwin/swigwin-4.0.2/swigwin-4.0.2.zip/download?use_mirror=pilotfiber"
    if(![System.IO.Directory]::Exists( $supportPathRoot+"swigwin" ))
    {
        Write-Host "Downloading Swigwin..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $swigwinDownload -OutFile ($downloadsPathRoot+"swigwin.zip") -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
        
        Write-Host "Extracting Cmake" -ForegroundColor Yellow
        unzip ($downloadsPathRoot+"swigwin.zip") $supportPathRoot

        
        $folder = Get-ChildItem ($supportPathRoot+'swigwin-*/') -Directory
        Move-Item $folder ($supportPathRoot+'swigwin/')
    }
    else
    {
        Write-Host "Cmake already exists";
    }

    ### Download Kicad
    if(![System.IO.Directory]::Exists($PSScriptRoot+'kicad/'))
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
        [ValidateSet('x86', 'x64')]
        [string]$arch
    )

    $triplet = "$arch-windows"
    return $triplet;
}


function Prepare-Vcpkg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [ValidateSet('x86', 'x64')]
        [string]$arch
    )

    # Patch vcpkg
    $patches = Get-ChildItem .\patches\*.patch
    foreach ($patch in $patches) {
        git apply $patch --directory vcpkg --whitespace=fix
    }

    # Bootstrap vcpkg
    Push-Location $settings.VcpkgPath
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
    $vcpkgCopyPaths = @( "boost",
                        "cairo",
                        "curl", 
                        "glew",
                        "gettext",
                        "glm",
                        "icu",
                        "ngspice",
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
    Push-Location ($PSScriptRoot+"kicad")
    git reset --hard origin/master
    git clean -f
    git pull --rebase
    Pop-Location
}

if( $Config )
{
    Set-Config -VcpkgPath $VcpkgPath
}

if( $Setup )
{
    Start-Setup
}

if( $Vcpkg )
{
    Prepare-Vcpkg -arch $Arch
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
    Start-Package
}