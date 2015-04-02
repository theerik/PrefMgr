# PrefMgr
Tcl package for managing application and system preferences and persistent 
data

The PrefMgr (Preferences Manager) package provides methods for setting and 
retrieving persistent data values, using a key/value paradigm.  Two classes 
of data are supported: system-wide common data, and application-specific 
local data. Typical uses for system data are descriptors of hardware 
interfaces (e.g., COM port ID's) or paths to system resources.  

The system preferences are stored in a canonical location (varies per OS); 
the local preferences are stored in a file in the current directory 
(filename should be specified in the calling script; default is prefs.ini).  
Data in files is stored in key=value format.

When getting the data associated with a key, normally the local application-
specific value is returned; if no such key exists locally, the system value 
is returned; if no such key exists, the passed-in default value is returned; 
if that does not exist, an empty string is returned.

Detailed documentation created by Pycco as a literate programming output can 
be found in docs/PrefMgr.html.

Interface: <br>
  PrefMgr::initPrefs local-data-file-name <br>
  PrefMgr::getPref key optional-default <br>
  PrefMgr::getSysPref key optional-default <br>
  PrefMgr::setPref key value <br>
  PrefMgr::setSysPref key value <br>
  PrefMgr::showPrefs <br>
  PrefMgr::setDebug <br>
