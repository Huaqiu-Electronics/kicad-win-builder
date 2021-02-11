import site
import os

directory = os.path.dirname(os.path.realpath(__file__))
site.addsitedir(os.path.join(directory, '..\\..\\Lib'))
site.addsitedir(os.path.join(directory, '..\\..\\Lib\\site-packages'))