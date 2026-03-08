./build.ps1 -Config -UseMsvcCmake $False
./build.ps1 -Init
./build.ps1 -Env -Arch x64
./build.ps1 -Build -Latest -Arch x64 -BuildType Release
./build.ps1 -PreparePackage  -Arch x64   -BuildType Release
./build.ps1 -Package  -PackType Nsis   -Arch x64   -BuildType Release