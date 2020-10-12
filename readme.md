KiCad-Winbuilder provides the means to build up-to-date KiCad binaries

Instructions:
=========================================

1. Download (and install) CMake from here: https://cmake.org/download/
2. Git clone this repository to a location on your machine.
3. Run make_all.bat from the freshly cloned git repository



Possible issues (and workarounds):
========================================

**Issue**:
Windows username has space in it, which will cause issues with build process (related to windres.exe not accepting spaces)

**Workaround**:
1. Launch msys2_shell.bat
2. run command '/usr/bin/mkpasswd > /etc/passwd'
3. exit msys2_shell.bat
4. open /etc/passwd in text editor and remove spaces from the username and the home directory locations (columns 1 and 5 from memory.. but it should be obvious)
5. save file and close
6. rename user home directory to remove space character
