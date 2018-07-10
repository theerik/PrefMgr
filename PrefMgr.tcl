#--------------------------------------------------------------------------
#
# FILENAME:    PrefMgr.tcl
#
# AUTHOR:      theerik@github
#
# DESCRIPTION:  Preferences Manager provides methods for setting and
#               retrieving persistent data values.  Two classes of data are
#               supported:  system-wide common data, and application-
#               specific data.  Typical uses for system data are descriptors
#               of hardware interfaces (e.g., port ID's) or paths to system
#               resources.
#
#--------------------------------------------------------------------------
#
# Copyright 2010-2017, Erik N. Johnson
#
# This package documentation is auto-generated with
# Pycco: <https://pycco-docs.github.io/pycco/>
#
# Use "pycco filename" to re-generate HTML documentation in ./docs .
#
# #########################################################################

package provide PrefMgr 0.7.1

namespace eval PrefMgr {
   variable preferences
   variable sysPreferences
   variable prefFileName
   variable initDone
   variable sysInitDone
   variable debug
   variable sysFileName
   variable packageDir

   namespace export initPrefs getPref getSysPref setSysPref setPref \
                    showPrefs setDebug
}

set ::PrefMgr::packageDir [file dirname [info script]]

#--------------------------------------------------------------------------
# The preferences files are stored in canonical locations.
#
# The system preferences will be in *$env(LOCALAPPDATA)/sysprefs.ini*,
# which is guaranteed to be defined in Windows and inherited for Cygwin,
# and is common for the system.
#
# Update (v. 0.6): *$env(LOCALAPPDATA)* is only defined for Windows 7.  For
# XP, the environment variable is *$env(APPDATA)*, which in Win7 is in the
# "Roaming" subdirectory, following the user rather than the system.  Sigh.
# Since system preferences are explicitly local to the system and should
# NOT follow a user account, we'll look for LOCALAPPDATA first, then fail
# over to APPDATA.  Hopefully Vista should be OK with one of the two, but
# I don't have a Vista system to check it, so for now I'm just assuming.
# (Update: run on a friend's system, works correctly.)
# Also, for non-Windows systems, add *env(HOME)* and a final *nix failover
# of ~/.  I have no idea what a Mac does, so I hope this is enough.
# Update (post v. 0.7): Now on Win 10, and LOCALAPPDATA continues to work.
# Still don't have a Mac to test on.
#
#
if {[info exists ::env(LOCALAPPDATA)]} {
   set ::PrefMgr::sysFileName [file join {*}[file split $::env(LOCALAPPDATA)] \
         "sysprefs.ini"]
} elseif {[info exists ::env(APPDATA)]} {
   set ::PrefMgr::sysFileName [file join {*}[file split $::env(APPDATA)] \
         "sysprefs.ini"]
} elseif {[info exists ::env(HOME)]} {
   set ::PrefMgr::sysFileName [file join {*}[file split $::env(HOME)] \
         "sysprefs.ini"]
} else {
   set ::PrefMgr::sysFileName [file join "~" "sysprefs.ini"]
}

# Application preferences will be in whatever file the main application
# defines when calling initPrefs (defaults to ./prefs.ini) and since
# it's normally unique to the current directory, a given tool run in
# different directories can have different saved preferences.  The app
# preferences filename can be overridden when initPrefs is called, and
# *should* be overridden to be unique for each app using the package.
if {![info exists ::PrefMgr::prefFileName]} {
   set ::PrefMgr::prefFileName "prefs.ini"
}

#--------------------------------------------------------------------------
# Only init the debug flag if user did not already set it, allowing user to
# pre-enable the debug flag when loading the package to debug load issues.
# This requires the user to add an extra line of code to deal with
# the namespace issues:
#
#     namespace eval PrefMgr {variable debug}
#     set ::PrefMgr::debug true
#
# For non-load-time debugging, the *setDebug* method allows the package user
# to dynamically enable debugging.
#
if {![info exists ::PrefMgr::debug]} {
   set ::PrefMgr::debug false
}

proc ::PrefMgr::setDebug {{debugFlag false}} {
   set ::PrefMgr::debug $debugFlag
}

#--------------------------------------------------------------------------
# *_loadPrefFile* is a helper proc that opens the input file and loads
# the contents into an array.  The name of the array is passed in to upvar
# it to support either the local or the system preferences files.
#
# If the file cannot be opened, we will print an error message then open the
# location where the file *should* be and touch it, creating a zero-length
# file so that we only complain once.
#
# Once the file is opened, we process the file line by line, dumping the
# input lines when in debug mode.
# We skip any comments, defined as lines starting with `;` or `#`.
# (";" is .ini file convention, "#" is Tcl convention.)  If a line isn't
# a comment, it's expected to have a format of `key=value`, and we complain
# if it doesn't (but continue anyway).
#
proc ::PrefMgr::_loadPrefFile {fname arrayName} {
   upvar 0 $arrayName prefA

   if {[catch {open $fname r} prefsHandle]} {
      puts $::PrefMgr::DebugHandle "Preferences file ($fname) not found. \
            Creating empty file."
      set prefsHandle [open $fname w]
      close $prefsHandle
   } else {
      if {$::PrefMgr::debug} {
         puts $::PrefMgr::DebugHandle "\tpreferences file found: \
               [glob -nocomplain $fname].\n"
         puts [format "%30s : %s" "Key" "Value"]
      }
      set done [gets $prefsHandle line]
      while {$done != -1} {
         if {!([string index $line 0] == ";" || $line == "" || \
               [string index $line 0] == "#")    } {
            if {[regexp {([^=]+)=(.*)} $line match key value]} {
               set prefA($key) $value
               if {$::PrefMgr::debug} {
                  puts [format "%30s : %s" $key $value]
               }
            } else {
               puts "Uninterpretable line: $line"
            }
         }
         set done [gets $prefsHandle line]
      }
      close $prefsHandle
   }
}

#--------------------------------------------------------------------------
# *_dumpPrefFile* is a helper proc that opens the output file, writes
# out the values of the preferences array, and closes the file again.
#
proc ::PrefMgr::_dumpPrefFile {fname arrayName} {
   upvar 0 $arrayName prefA
   set prefsHandle [open $fname w]
   if [string match "*sysPref*" $arrayName] {
      puts $prefsHandle "; System Preferences: $fname"
   } else {
      puts $prefsHandle "; Application Preferences: $fname"
   }
   puts $prefsHandle "; "
   puts $prefsHandle "; WARNING: This file is auto-generated by PrefMgr."
   puts $prefsHandle ";          Any formatting changes will be lost."
   puts $prefsHandle "; "

   foreach {outkey outvalue} [array get prefA] {
      puts $prefsHandle "$outkey=$outvalue"
   }
   close $prefsHandle
}

#--------------------------------------------------------------------------
# *initPrefs* opens the local preferences file and reads it into the
# main array.  Uses a default name if no file name is provided; saves
# the name for use when saving changes.
#
proc ::PrefMgr::initPrefs {{prefFile "./prefs.ini"}} {
   set ::PrefMgr::prefFileName $prefFile
   ::PrefMgr::_loadPrefFile $prefFile ::PrefMgr::preferences
   set ::PrefMgr::initDone true
}

#--------------------------------------------------------------------------
# *getPref* is a simple fetch from the preferences array, but we
# have to handle it gracefully if the key doesn't exist.  First, in
# case the user grabbed it from the wrong array, check the system
# array, which will return the value passed in as the default if it
# fails too. Finally, if there was no default, return a null string.
#
proc ::PrefMgr::getPref {key {default ""}} {
   if {!$::PrefMgr::initDone} {
      puts $::PrefMgr::DebugHandle "WARNING - Attempt to access preferences \
            before init.  Key = $key."
   }
   if {[catch {set value $::PrefMgr::preferences($key)}]} {
      return [::PrefMgr::getSysPref $key $default]
   }
   if {$::PrefMgr::debug} {
      puts $::PrefMgr::DebugHandle "getting app key = $key, value = $value"
   }
   return $value
}

#--------------------------------------------------------------------------
# *getSysPref* is the same as getPref, but only looks in the system
# preferences array.  If the key doesn't exist, return whatever the
# programmer defined as the default.  If there was no default,
# return a null string.
#
proc ::PrefMgr::getSysPref {key {default ""}} {
   if {[catch {set value $::PrefMgr::sysPreferences($key)}]} {
      if {$::PrefMgr::debug} {
         puts $::PrefMgr::DebugHandle "\tkey $key not found. \
                              Returning \'$default\' as default.\n"
      }
      return $default
   }
   if {$::PrefMgr::debug} {
      puts $::PrefMgr::DebugHandle "getting sys key = $key, value = $value"
   }
   return $value
}

#--------------------------------------------------------------------------
# *setPref* stores the value into the array, then the array must be flushed
# out to the file.  We do not want to rely on a clean exit to write this out.
#
proc ::PrefMgr::setPref {key value} {
   set ::PrefMgr::preferences($key) $value
   if {$::PrefMgr::debug} {
      puts $::PrefMgr::DebugHandle "set app key = $key, value = $value"
   }
   ::PrefMgr::_dumpPrefFile $::PrefMgr::prefFileName ::PrefMgr::preferences
}

#--------------------------------------------------------------------------
# *setSysPref* is the same as setPref, but writes to the system
# file, not the local one.
#
proc ::PrefMgr::setSysPref {key value} {
   set ::PrefMgr::sysPreferences($key) $value
   if {$::PrefMgr::debug} {
      puts $::PrefMgr::DebugHandle "set sys key = $key, value = $value"
   }
   ::PrefMgr::_dumpPrefFile $::PrefMgr::sysFileName ::PrefMgr::sysPreferences
}

#--------------------------------------------------------------------------
# *showPrefs* displays all key/value pairs, sorted alphabetically.
#
proc ::PrefMgr::showPrefs {} {
   set sortList {}
   puts ""
   puts "Keys from local file ($::PrefMgr::prefFileName):"
   puts "--------------------------------------------"
   foreach {key value} [array get ::PrefMgr::preferences] {
      lappend sortList [list $key $value]
   }
   set sortList [lsort -index 0 $sortList]
   foreach pair $sortList {
      puts [format "%30s : %s" {*}$pair]
   }
   set sortList {}
   puts ""
   puts "Keys from System preferences ($::PrefMgr::sysFileName):"
   puts "----------------------------------------------"
   foreach {key value} [array get ::PrefMgr::sysPreferences] {
      lappend sortList [list $key $value]
   }
   set sortList [lsort -index 0 $sortList]
   foreach pair $sortList {
      puts [format "%30s : %s" {*}$pair]
   }
   puts ""
}

#--------------------------------------------------------------------------
# -------------->  Run on load - don't wait for init  <-------------
#
# When the package is loaded, try to open the system preferences file at once.
# Don't wait for invocation. But only do it once. *sysInitDone* marks it as run.
#
proc ::PrefMgr::runOnLoad {} {
   if {$::PrefMgr::debug} {
      puts "\tPrefMgr.tcl loading\n"
   }
   if {!([info exists ::PrefMgr::sysInitDone] && $::PrefMgr::sysInitDone)} {
      if {![info exists ::PrefMgr::DebugHandle]} {
         set ::PrefMgr::DebugHandle stderr
      }
      set ::PrefMgr::initDone false

      # If the system preferences file does not exist, create an empty file
      # in the canonical location for us to find in the future.
      set sysFileName $::PrefMgr::sysFileName
      if {![file exists $::PrefMgr::sysFileName]} {
         puts $::PrefMgr::DebugHandle "Default system preferences file \
               ($sysFileName) not found."
         puts $::PrefMgr::DebugHandle "Creating new empty file in default \
               location ($sysFileName)"
         set prefsHandle [open $::PrefMgr::sysFileName w]
         close $prefsHandle
         set ::PrefMgr::sysInitDone true
         return
      }
      ::PrefMgr::_loadPrefFile $sysFileName ::PrefMgr::sysPreferences
      set ::PrefMgr::sysInitDone true
   }
}

::PrefMgr::runOnLoad
