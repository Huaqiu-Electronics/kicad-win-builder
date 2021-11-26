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
import re
import sys

sys.path = []

directory = os.path.dirname(os.path.realpath(__file__))
site.addsitedir(os.path.join(directory, '..\\..\\DLLs'))
site.addsitedir(os.path.join(directory, '..\\..\\Lib'))
site.addsitedir(os.path.join(directory, '..\\..\\Lib\\site-packages'))

# Python is a language designed by committee 
# with absolutely zero consistency as a result and half baked everything
# pip uses both distutils and sysconfig paths for `install` operations
# We overwrite those using PYTHONUSERBASE for `sysconfig` and
# manually overwriting the site.USER_BASE/site.USER_SITE variables for `distutils`
# Uninstall however does not do the logical thing
# It is driven by sys.path which is appended to by site.addsitedir

self_dir_path = str(pathlib.Path(__file__).parent.resolve())
# extract the version number
m = re.search(r'\\(\d.+)\\bin', self_dir_path)
version = m.group(1)

# sysconfig override
user_base = os.path.expanduser(f'~\\Documents\\KiCad\\{version}\\3rdparty\\')
os.environ["PYTHONUSERBASE"] = user_base

# distutils overrides
# Even worse, sysconfig has lots of hardcoded logic to 
# always append "Python{MAJOR}.{MINOR}" to the PYTHONUSERBASE...which we can spend a hundred lines overriding
# or reproduce it for the `distutils` override
python_ver_nodot = sys.winver.replace('.', '')
user_site = os.path.expanduser(f'~\\Documents\\KiCad\\{version}\\3rdparty\\Python{python_ver_nodot}\\site-packages')
# Now override the site params which drive distutils
site.PREFIXES = [ self_dir_path ]
site.USER_BASE = user_base
site.USER_SITE = user_site

# sys.paths override
# Because pip ignores all of the above and uses sys.paths for finding packages to remove
site.addsitedir(user_site)