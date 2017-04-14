/*
 * Valadate - Unit testing library for GObject-based libraries.
 * Copyright (C) 2016  Chris Daley <chebizarro@gmail.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.

 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 * 
 * Authors:
 * 	Chris Daley <chebizarro@gmail.com>
 */
 
namespace Valadate {

	public class TestAssembly : Assembly {

		public File srcdir {get;set;}
		public File builddir {get;set;}

		public TestOptions options {get;set;}

		private GLib.Module module;
		
		public TestAssembly(string[] args) throws Error {
			base(File.new_for_path(args[0]));
			options = new TestOptions(args);
			setup_dirs();
		}
		
		private TestAssembly.copy(TestAssembly other) throws Error {
			base(other.binary);
			options = other.options;
		}
		
		private void setup_dirs() {

			var buildstr = Environment.get_variable("G_TEST_BUILDDIR");

			if(buildstr == null) {
				builddir = binary.get_parent();
				if(builddir.get_basename() == ".libs")
					builddir = builddir.get_parent();
			} else {
				builddir = File.new_for_path(buildstr);
			}

			var srcstr = Environment.get_variable("G_TEST_SRCDIR");
			
			if(srcstr == null) {
				// we're running outside the test harness
				// check for buildir!=srcdir
				// this currently on checks for autotools
				if(!builddir.get_child("Makefile.in").query_exists()) {
					// check for Makefile in builddir and extract VPATH
					var makefile = builddir.get_child("Makefile");
					if(makefile.query_exists()) {
						var reader = new DataInputStream(makefile.read());
						while(true) {
							var line = reader.read_line();
							if(line == null) {
								break;
							} else if(line.has_prefix("VPATH = ")) {
								srcstr = line.split(" = ")[1];
								break;
							}
						}
					}
				}
			}
			
			if(srcstr == null)
				srcdir = builddir;
			else
				srcdir = File.new_for_path(srcstr);

			var mesondir = srcdir.get_child(Path.get_basename(binary.get_path()) + "@exe");

			if(mesondir.query_exists())
				srcdir = mesondir;

		}
	
		public override Assembly clone() throws Error {
			return new TestAssembly.copy(this);
		}

		private void load_module() throws AssemblyError {
			module = GLib.Module.open (binary.get_path(), ModuleFlags.BIND_LAZY);
			if (module == null)
				throw new AssemblyError.LOAD(GLib.Module.error());
			module.make_resident();
		}
		
		public void* get_method(string method_name) throws AssemblyError {
			if(module == null)
				load_module();
			void* function;
			if(module.symbol (method_name, out function))
				if (function != null)
					return function;
			throw new AssemblyError.METHOD(GLib.Module.error());
		}
	
	}
}
