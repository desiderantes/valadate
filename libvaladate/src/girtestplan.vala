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

	public class GirTestPlan : Object, TestPlan {

		public Assembly assembly {get;construct set;}
		public TestOptions options {get;set;}
		public TestConfig config {get;set;}
		public TestResult result {get;set;}
		public TestRunner runner {get;set;}
		public TestSuite root {get;protected set;}
		public File plan {get;construct set;}

		internal delegate Type GetType(); 

		private TestSuite testsuite;
		private TestCase testcase;
		private string currpath;
		
		private XmlFile xmlfile; 

		construct {
			try {
				//assembly = options.assembly;
				options = ((TestAssembly)assembly).options;
				testsuite = root = new TestSuite("/");
				load();
			} catch (Error e) {
				error(e.message);
			}
		}

		private void load() throws ConfigError {
			setup_context();
			visit_config();
			visit_test_result();
			visit_test_runner();
			visit_root();
		}

		private void setup_context() throws ConfigError {
			try {
				xmlfile = new XmlFile(plan);
				xmlfile.register_ns("xmlns", "http://www.gtk.org/introspection/core/1.0");
				xmlfile.register_ns("c", "http://www.gtk.org/introspection/c/1.0");
				xmlfile.register_ns("glib", "http://www.gtk.org/introspection/glib/1.0");
			} catch (Error e) {
				throw new ConfigError.TESTPLAN(e.message);
			}
		}

		private void visit_config() {
			var conf = xmlfile.eval("//xmlns:class[@parent='ValadateTestConfig']");
			Type ctype;
			if(conf.size == 1) {
				var node = conf[0];
				string node_type_str = node->get_prop("get-type");
				GetType node_get_type = (GetType)assembly.get_method(node_type_str);
				ctype = node_get_type();
			} else {
				ctype = typeof(TestConfig);
			}
			config = Object.new(ctype, "options", options, null) as TestConfig;
		}

		private void visit_test_result() {
			var res = xmlfile.eval("//xmlns:class[@parent='ValadateTestResult']");
			Type ctype;
			if(res.size == 1) {
				var node = res[0];
				string node_type_str = node->get_prop("get-type");
				GetType node_get_type = (GetType)assembly.get_method(node_type_str);
				ctype = node_get_type();
			} else {
				ctype = typeof(TapTestResult);
			}
			result = Object.new(ctype, "config", config) as TestResult;
		}
		
		private void visit_test_runner() {
			var res = xmlfile.eval("//xmlns:class[@implements='ValadateTestRunner']");
			Type ctype;
			if(res.size == 1) {
				var node = res[0];
				string node_type_str = node->get_prop("get-type");
				GetType node_get_type = (GetType)assembly.get_method(node_type_str);
				ctype = node_get_type();
				TestRunner.register_default(ctype);
			}
			runner = TestRunner.new(config);
		}

		private void visit_root() {
			var ns = xmlfile.eval("//xmlns:namespace");
			
			foreach (var node in ns) {
				var tsname = node->get_prop("prefix");
				if(options.running_test != null)
					if(tsname != options.running_test.split("/")[1])
						continue;
				currpath = "/" + tsname;
				var ts = new TestSuite(tsname);
				testsuite.add_test(ts);
				testsuite = ts;
				visit_testsuite(node);
			}
		}
		
		private void visit_testsuite(Xml.Node* suitenode) {
			var expression = "%s/xmlns:class".printf(suitenode->get_path());
			var res = xmlfile.eval (expression);

			foreach (var node in res) {
				string node_type_str = node->get_prop("get-type");
				GetType node_get_type = (GetType)assembly.get_method(node_type_str);
				var node_type = node_get_type();

				if(!node_type.is_a(typeof(Valadate.Test)) || node_type.is_abstract())
					continue;

				var testname = node->get_prop("name");
				
				if(options.running_test != null)
					if(testname != options.running_test.split("/")[2])
						continue;

				var oldpath = currpath;
				currpath += "/" + testname;
				var test = GLib.Object.new(node_type, "name", testname, "label", currpath) as Test;
				testsuite.add_test(test);

				if(node_type.is_a(typeof(TestSuite))) {
					testsuite = test as TestSuite;
					//visit_testsuite(node);
				} else if (node_type.is_a(typeof(TestCase))) {
					testcase = test as TestCase;
					visit_class(node_type);
				}
				currpath = oldpath;
			}
		}
		
		private void visit_class(Type classtype)
			requires(classtype.is_a(typeof(Test)))
		{
			if(classtype == typeof(TestCase))
				return;

			var expression = "//xmlns:class[@glib:type-name='%s']/xmlns:method".printf(classtype.name());
			var res = xmlfile.eval(expression);
			
			foreach (var method in res) {

				string name = method->get_prop("name");

				if(options.running_test != null)
					if(name != options.running_test.split("/")[3])
						continue;

				var oldpath = currpath;
				currpath += "/" + name; 

				bool throwserr = (method->get_prop("throws") == null) ? false : true;
				string label = name;
				bool istest = false;
				bool skip = false;

				if(name.has_prefix("test_")) {
					istest = true;
					label = label.substring(5);
				}

				if(name.has_prefix("_test_")) {
					skip = istest = true;
					label = label.substring(6);
				}

				label = label.replace("_", " ");
				
				var child = method->children;
				while(child != null) {
					if(child->name == "annotation") {
						var attname = child->get_prop("name") ?? child->get_prop("key");
						if(attname.has_prefix("test."))
							istest = true;
						if(attname == "test.name")
							label = child->get_prop("value");
						if(attname == "test.skip")
							skip = (child->get_prop("value") == "yes") ? true : false;
					}
					if(child->name == "return-value") {
						var retchild = child->children;
						while(retchild->name != "type") { retchild = retchild->next; };
						if(retchild->get_prop("name") != "none")
							istest = false;
					}
					if(child->name == "parameters")
						istest = false;
					child = child->next;
				}
			
				if(!istest) {
					currpath = oldpath;
					continue;
				}
			
				var tcase = testcase;
				TestPlan.TestMethod testmethod = null;
				if(skip) {
					testmethod = () => { tcase.skip(@"Skipping Test $(label)"); };
				} else {
					if(options.running_test != null || !config.run_async) {
						var method_cname = method->get_prop("identifier");
						testmethod = (TestPlan.TestMethod)assembly.get_method(method_cname);
					} else {
						testmethod = () => { assert_not_reached(); };
					}
				}
				if(testmethod != null) {
					tcase.add_test(name, () => { testmethod(tcase); }, oldpath + "/" + label);
				}
				currpath = oldpath;
			}
			visit_class(classtype.parent());
		}

		public void run() {
			runner.run_all(this);
		}
		
	}

}
