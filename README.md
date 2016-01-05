This is a fork of Valadate, updated to Vala 0.30 and Autotools

To build

./autogen.sh
make



Valadate
========

Valadate is a unit testing framework based on GLib Testing. It is primarily
intended for testing code written in [Vala][vala], but can be used with any
GObject-based code.

Features
--------

  * Automatic test discovery like JUnit or .NET testing framework.

    Tests can be automatically found in a shared library using either
    .vapi ([Vala][vala] API description) or [.gir][gir] file.

  * Running tests for all parameters from specific set.

    A test fixture can define properties and sets of values for them and the
    discovered test methods will automatically be run for all of them.

  * Utility functions for waiting in a main loop until specified event or
    timeout occurs.

  * Support for asynchronous tests. Method declared async in vala will be
    automatically run under main loop until completion or configurable
    timeout.

  * Utility functions providing temporary directory to tests.

    With support for initializing the temporary directory by storing data,
    copying specified files there, and running a shell snippet.

Planned features
----------------

  * Automatically running each test in a separate child process.

  * Running next tests even after failure.

    It requires chaning the runner for that.

  * Skipped tests and expected failures.

  * Initializing test directories by extracting zip and/or tar.gz
    archives.

  * Generic tests.

    Support for providing a list of types a generic test fixture should be
    instantiated for. 

Dependencies
------------

  * [GLib][glib] 2.20.0 or later
  * [Vala][vala] 0.30.0 or later
  * [GOjbect-introspection][gir] 1.0.0 or later

Copyright
---------

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published
by the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public License
along with this program in the file COPYING.  You should have received
a copy of the GNU General Public License refered therein along with this
program in the file GPL-3.  If not, see <http://www.gnu.org/licenses/>.

[vala]: http://live.gnome.org/Vala
[gir]: http://live.gnome.org/GObjectIntrospection
[glib]: http://www.gtk.org/ (The GTK+ Project)
