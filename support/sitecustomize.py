#
# This program source code file is part of KiCad, a free EDA CAD application.
#
# Copyright (C) 2021 Mark Roszko <mark.roszko@gmail.com>
# Copyright (C) 2021 KiCad Developers
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#  MA 02110-1301, USA.
#

import site
import os
import pathlib
import sys
import array

def get_file_version(filename):
    from ctypes import windll, create_string_buffer, c_void_p, byref, c_uint, wstring_at, string_at

    """
    Extract information from a file.
    Original from https://stackoverflow.com/questions/42604493/verqueryvaluew-issue-python-3
    """
    # Get size needed for buffer (0 if no info)
    size = windll.version.GetFileVersionInfoSizeW(filename, None)
    # If no info in file -> empty string
    if not size:
        return 'Failed'

    # Create buffer
    file_version_buffer = create_string_buffer(size)

    # Load file informations into buffer res
    windll.version.GetFileVersionInfoW(filename, None, size, file_version_buffer)

    # r is the void pointer into the buffer
    r = c_void_p(0)
    # l is the length read at the buffer pointer
    l = c_uint(0)

    # Look for codepages
    success = windll.version.VerQueryValueW(file_version_buffer, u'\\VarFileInfo\\Translation', byref(r), byref(l))

    # If no codepage -> empty string
    if not l.value:
        return ''
    
    # Take the first codepage (what else ?)
    codepages = array.array('H', string_at(r.value, l.value))
    codepage = tuple(codepages[:2].tolist())

    # Extract information
    windll.version.VerQueryValueW(file_version_buffer, ('\\StringFileInfo\\%04x%04x\\' + 'ProductVersion') % codepage, byref(r), byref(l))

    #-1 length because it includes null
    return wstring_at(r.value, l.value-1)
    
def get_user_docu_path():
    from ctypes import windll, wintypes, create_unicode_buffer
    CSIDL_PERSONAL = 5
    SHGFP_TYPE_CURRENT = 0
    
    buf = create_unicode_buffer(wintypes.MAX_PATH)
    windll.shell32.SHGetFolderPathW(0, CSIDL_PERSONAL, 0, SHGFP_TYPE_CURRENT, buf)
    
    return buf.value

sys.path = []

current_directory = os.path.dirname(os.path.realpath(__file__))
site.addsitedir(os.path.join(current_directory, '..\\..\\DLLs'))
site.addsitedir(os.path.join(current_directory, '..\\..\\Lib'))
site.addsitedir(os.path.join(current_directory, '..\\..\\Lib\\site-packages'))

# Python is a language designed by committee 
# with absolutely zero consistency as a result and half baked everything
# pip uses both distutils and sysconfig paths for `install` operations
# We overwrite those using PYTHONUSERBASE for `sysconfig` and
# manually overwriting the site.USER_BASE/site.USER_SITE variables for `distutils`
# Uninstall however does not do the logical thing
# It is driven by sys.path which is appended to by site.addsitedir

kicad_path = os.path.normpath(os.path.join(current_directory, '..\\..\\kicad.exe'))

kicad_version = ""
kicad_product_version = ""
try:
    kicad_product_version = get_file_version(kicad_path)
except:
    pass

if kicad_product_version:
    version_bits = kicad_product_version.split('.')
    if len(version_bits) >= 2:
        kicad_version = "{}.{}".format(version_bits[0],version_bits[1])

user_docus_path = get_user_docu_path()

if kicad_version:
    # sysconfig override
    user_base = os.path.join(user_docus_path, f'KiCad\\{kicad_version}\\3rdparty\\')
    os.environ["PYTHONUSERBASE"] = user_base

    # distutils overrides
    # Even worse, sysconfig has lots of hardcoded logic to 
    # always append "Python{MAJOR}.{MINOR}" to the PYTHONUSERBASE...which we can spend a hundred lines overriding
    # or reproduce it for the `distutils` override
    python_ver_nodot = sys.winver.replace('.', '')
    user_site = os.path.join(user_docus_path, f'KiCad\\{kicad_version}\\3rdparty\\Python{python_ver_nodot}\\site-packages')
    # Now override the site params which drive distutils
    site.PREFIXES = [ current_directory ]
    site.USER_BASE = user_base
    site.USER_SITE = user_site

    # sys.paths override
    # Because pip ignores all of the above and uses sys.paths for finding packages to remove
    site.addsitedir(user_site)