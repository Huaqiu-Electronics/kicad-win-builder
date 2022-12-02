Add-Type -TypeDefinition @'
public enum Arch {
    x86,
    x64,
    arm,
    arm64
}
'@

Add-Type -TypeDefinition @'
public enum ExitCodes {
    Ok = 0,
    DownloadChecksumFailure = 1,
    VcpkgInstallPortsFailure = 2,
    CMakeGenerationFailure = 3,
    CMakeBuildFailure = 4,
    CMakeInstallFailure = 5,
    NsisFailure = 6,
    DownloadExtractFailure = 7,
    GitCloneFailure = 8,
    EnsurePip = 9,
    WxPythonRequirements = 10,
    GitResetFailure = 11,
    GitCleanFailure = 12,
    GitPullRebaseFailure = 13,
    UnsupportedSwitch = 14,
    InkscapeSvgConversion = 15,
    InvalidMsixVersion = 16,
    MakePriFailure = 17,
    MakeAppxFailure = 18,
    SignFail = 19,
    PdbPackageFail = 20,
    PythonManifestPatchFailure = 21,
    ExtraRequirements = 22,
    ReleaseDoesNotExit = 23,
    GitCheckoutBranch = 24,
    GitCheckoutTag = 25,
    GitFetch = 26,
    CmakeLocation = 27,
    ConfigError = 28
}
'@

Add-Type -TypeDefinition @'
public enum SourceType {
    git,
    tar
}
'@

# Load the .NET compression library, powershell's expand-archive is horrid in performance
Add-Type -Assembly 'System.IO.Compression.FileSystem'

$BuilderPaths = @{
    SupportRoot           = ''
    DownloadsRoot         = ''
    OutRoot               = ''
    BuildRoot             = ''
    KiBuildEnv            = ''
}

New-Variable -Name BuilderPaths -Value $BuilderPaths -Scope Script -Force


#Get public and private function definition files.
$Public  = @( Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue )
$Private = @( Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue )

#Dot source the files
Foreach($import in @($Public + $Private))
{
    Try
    {
        . $import.fullname
    }
    Catch
    {
        Write-Error -Message "Failed to import function $($import.fullname): $_"
    }
}

Export-ModuleMember -Function $Public.Basename