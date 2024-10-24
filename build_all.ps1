./build.ps1 -Config -UseMsvcCmake $False
./build.ps1 -Init
./build.ps1 -Env -Arch x64
./build.ps1 -Vcpkg -Latest -Arch x64
./build.ps1 -Build -Latest -Arch x64 -BuildType Release