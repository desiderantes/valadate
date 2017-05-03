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
 
namespace Valadate.Drivers {

	public class Driver : Object, VapiDriver {
		
		private Vala.CodeContext context;
		
		public Driver() {
			setup_context();
		}

		public void load_test_plan(VapiTestPlan plan) throws Error {
			context.add_source_file (new Vala.SourceFile (
				context, Vala.SourceFileType.PACKAGE, plan.plan.get_path()));
			var parser = new Vala.Parser ();
			parser.parse (context);
			var gatherer = new ClassGatherer(plan.assembly);
			context.accept(gatherer);
			var visitor = new TestVisitor(plan, gatherer);
			context.accept(visitor);
		}

		private void setup_context() {
			context = new Vala.CodeContext ();
			Vala.CodeContext.push (context);
			context.report.enable_warnings = false;
			context.report.set_verbose_errors (false);
			context.verbose_mode = false;
		}

	}

	
	public class ClassGatherer : Vala.CodeVisitor {
		
		public HashTable<Type, Vala.Class> classes = 
			new HashTable<Type, Vala.Class>(direct_hash, direct_equal);
		
		public Type config = typeof(TestConfig);
		public Type runner = typeof(AsyncTestRunner);
	
		private TestAssembly assembly;
	
		public ClassGatherer(TestAssembly assembly) {
			this.assembly = assembly;
		}
	
		public override void visit_namespace(Vala.Namespace ns) {
			ns.accept_children(this);
		}
		
		public override void visit_class(Vala.Class cls) {
			try {
				var classtype = find_type(cls);
				if (classtype.is_a(typeof(TestConfig)) && !classtype.is_abstract())
					config = classtype;
				else if (classtype.is_a(typeof(TestRunner)) && !classtype.is_abstract())
					runner = classtype;
				else
					classes.insert(classtype, cls);
			} catch (Error e) {
				warning(e.message);
			}
			cls.accept_children(this);
		}
		
		private Type find_type (Vala.Class cls) throws Error {
			unowned TestPlan.GetType node_get_type =
				(TestPlan.GetType)assembly.get_method (
					"%sget_type".printf (TestVisitor.get_ccode_lower_case_prefix (cls)));
			var classtype = node_get_type ();
			if (classtype.is_a (typeof (TestCase)) || classtype.is_a (typeof (TestSuite)))
				classes.insert (classtype, cls);

			return classtype;
		}

	}
	
	public class TestVisitor : Vala.CodeVisitor {
		public TestPlan plan {get;set;}
		internal delegate TestCase Constructor(); 
		
		private TestSuite testsuite;
		private TestCase testcase;
		private ClassGatherer gatherer;

		public TestVisitor(TestPlan plan, ClassGatherer gatherer) throws Error {
			this.plan = plan;
			this.gatherer = gatherer;
			visit_config();
			plan.result = new TestResult(plan.config);
			visit_test_runner();
		}

		private void visit_config() {
			plan.config = Object.new(gatherer.config, "options", plan.options) as TestConfig;
		}

		public void visit_test_runner() {
			TestRunner.register_default(gatherer.runner);
			plan.runner = TestRunner.new(plan.config);
		}

		public override void visit_namespace(Vala.Namespace ns) {
			if (ns.name != null) {
				var currpath = "/" + ns.get_full_name().replace(".","/");
				if(plan.config.in_subprocess)
					if(!plan.options.running_test.has_prefix(currpath))
						return;

				if(currpath.last_index_of("/") == 0)
					testsuite = plan.root;

				var ts = new TestSuite(ns.name);
				testsuite.add_test(ts);
				testsuite = ts;
			}
			ns.accept_children(this);
		}
		
		public override void visit_class(Vala.Class cls) {

			var label = "/%s".printf (cls.get_full_name ().replace (".","/"));

			if(!in_testpath (label))
				return;

			try {
				if (is_subtype_of(cls, typeof(TestCase)) && !cls.is_abstract) {
					unowned Constructor ctor = get_constructor(cls);
					testcase = ctor();
					testcase.name = cls.name;
					testcase.label = "/%s".printf(cls.get_full_name().replace(".","/"));
					testsuite.add_test(testcase);
					visit_testcase(cls);

				} else if (is_subtype_of(cls,typeof(TestSuite))) {
					visit_testsuite(cls);
				}
			} catch (Error e) {
				error(e.message);
			}
			cls.accept_children(this);
		}

		private bool in_testpath (string path) {
			if (plan.config.testpath == null)
				return true;

			var paths = path.split ("/");
			var testpaths = plan.config.testpath.split ("/");

			for (int i = 1; i < int.max (testpaths.length, paths.length); i++) {
				if (testpaths[i] == null || paths[i] == null)
					break;
				if (testpaths[i] == "" || paths[i] == "")
					break;
				if (testpaths[i] != paths[i])
					return false;
			}
			return true;
		}

		private bool is_subtype_of(Vala.Class cls, Type type) {
			var t = Type.from_name(cls.get_full_name().replace(".",""));
			if(t.is_a(type))
				return true;
			return false;
		}


		private unowned Constructor get_constructor (Vala.Class cls) throws Error {
			return (Constructor)plan.assembly.get_method (get_symbol_name (cls.default_construction_method));
		}

		public void visit_testcase(Vala.Class cls)  {

			var t = Type.from_name(cls.get_full_name().replace(".",""));
			var p = t.parent();
			if(p != typeof(TestCase)) {
				var basecls = gatherer.classes.get(p);
				if(basecls != null)
					visit_testcase(basecls);
			}

			foreach(var method in cls.get_methods()) {

				var currpath = "%s/%s".printf (testcase.label, method.name);

				if (plan.config.in_subprocess)
					if (plan.config.running_test != currpath)
						continue;

				if(!is_test(method))
					continue;

				var added = false;
				foreach(var test in testcase)
					if(test.name == method.name)
						added=true;
				if(added)
					continue;

				var adapter = new TestAdapter(method.name, plan.config.timeout);
				annotate_label(adapter);
				annotate(adapter, method);

				if(plan.config.in_subprocess && adapter.status != TestStatus.SKIPPED) {
					if(method.coroutine) {
						try {
						unowned TestPlan.AsyncTestMethod beginmethod =
							(TestPlan.AsyncTestMethod)plan.assembly.get_method (get_symbol_name (method));
						unowned TestPlan.AsyncTestMethodResult testmethod =
							(TestPlan.AsyncTestMethodResult)plan.assembly.get_method (get_finish_name (method));
							adapter.add_async_test(beginmethod, testmethod);
						} catch (Error e) {
							var message = e.message;
							adapter.add_test_method(()=> {debug(message);});
						}
					} else {
						try {
							TestPlan.TestMethod testmethod =
								(TestPlan.TestMethod)plan.assembly.get_method(get_symbol_name (method));
							adapter.add_test((owned)testmethod);
						} catch (Error e) {
							var message = e.message;
							adapter.add_test_method(()=> {debug(message);});
						}
					}
				}
				adapter.label = "%s/%s".printf (testcase.label,adapter.label);
				testcase.add_test(adapter);
			}
		}

		private void annotate_label(Test test) {
			if(test.name.has_prefix("test_")) {
				test.label = test.name.substring(5);
			} else if(test.name.has_prefix("_test_")) {
				test.label = test.name.substring(6);
				test.status = TestStatus.SKIPPED;
			} else if(test.name.has_prefix("todo_test_")) {
				test.label = test.name.substring(10);
				test.status = TestStatus.TODO;
			} else {
				test.label = test.name;
			}
			test.label = test.label.replace("_", " ");
		}

		private void annotate(TestAdapter adapter, Vala.Method method) {

			foreach(var attr in method.attributes) {
				if(attr.name == "Test") {
					if(attr.has_argument("name"))
						adapter.label = attr.get_string("name");
					if(attr.has_argument("skip")) {
						adapter.status = TestStatus.SKIPPED;
						adapter.status_message = attr.get_string("skip");
					} else if(attr.has_argument("todo")) {
						adapter.status = TestStatus.SKIPPED;
						adapter.status_message = attr.get_string("todo");
					} else if(attr.has_argument("timeout")) {
						adapter.timeout = int.parse(attr.get_string("timeout"));
					}
				}
			}
		}

		private bool is_test(Vala.Method method) {
			bool istest = false;
			
			if(method.is_virtual)
				foreach(var test in testcase)
					if(test.name == method.name)
						return false;
			
			if (method.name.has_prefix("test_") ||
				method.name.has_prefix("_test_") ||
				method.name.has_prefix("todo_test_"))
				istest = true;

			foreach(var attr in method.attributes)
				if(attr.name == "Test")
					istest = true;

			if(method.has_result)
				istest = false;
			
			if(method.get_parameters().size > 0)
				istest = false;
				
			return istest;
		}

		public void visit_testsuite (Vala.Class testclass) throws Error {
			unowned Constructor meth = get_constructor (testclass);
			var tsuite = meth () as TestSuite;
			tsuite.name = testclass.name;
			tsuite.label = "/%s".printf (testclass.get_full_name ().replace (".","/"));;
			testsuite.add_test (tsuite);
			testsuite = tsuite;
		}

		private string get_finish_name (Vala.Symbol sym) {
			var ccode = sym.get_attribute ("CCode");
			string finish_name = null;
			
			if (ccode != null) {
				finish_name = ccode.get_string ("cnfinish_nameame");
				if (finish_name == null) {
					finish_name = ccode.get_string ("finish_function");
				}
			}
			return finish_name ?? get_finish_name_for_basename (get_default_name (sym));
		}

		private string get_finish_name_for_basename (string basename) {
			string result = basename;
			if (result.has_suffix ("_async")) {
				result = result.substring (0, result.length - "_async".length);
			}
			return "%s_finish".printf (result);
		}

		private string get_symbol_name (Vala.Symbol sym) {
			var ccode = sym.get_attribute ("CCode");
			string name = null;
			
			if (ccode != null)
				name = ccode.get_string ("cname");
			return name ?? get_default_name (sym);
		}

		private static string get_default_name (Vala.Symbol sym) {
			if (sym is Vala.CreationMethod) {
				var m = (Vala.CreationMethod) sym;
				string infix = "new";
				if (m.name == ".new") {
					return "%s%s".printf (get_ccode_lower_case_prefix (m.parent_symbol), infix);
				} else {
					return "%s%s_%s".printf (get_ccode_lower_case_prefix (m.parent_symbol), infix, m.name);
				}
			} else if (sym is Vala.Method) {
				var m = (Vala.Method) sym;
				if (sym.name.has_prefix ("_")) {
					return "_%s%s".printf (get_ccode_lower_case_prefix (sym.parent_symbol), sym.name.substring (1));
				} else {
					return "%s%s".printf (get_ccode_lower_case_prefix (sym.parent_symbol), sym.name);
				}
			}
			return sym.name;
		}

		public static string get_ccode_lower_case_prefix (Vala.Symbol sym) {
			var ccode = sym.get_attribute ("CCode");
			string lower_case_prefix = null;

			if (ccode != null) {
				lower_case_prefix = ccode.get_string ("lower_case_cprefix");
				if (lower_case_prefix == null && (sym is Vala.ObjectTypeSymbol)) {
					lower_case_prefix = ccode.get_string ("cprefix");
				}
			}
			if (lower_case_prefix == null) {
				if (sym is Vala.Namespace) {
					if (sym.name == null) {
						lower_case_prefix = "";
					} else {
						lower_case_prefix = "%s%s_".printf (get_ccode_lower_case_prefix (sym.parent_symbol), Vala.Symbol.camel_case_to_lower_case (sym.name));
					}
				} else if (sym is Vala.Method) {
					// for lambda expressions
					lower_case_prefix = "";
				} else {
					lower_case_prefix = "%s%s_".printf (get_ccode_lower_case_prefix (sym.parent_symbol), get_ccode_lower_case_suffix (sym));
				}
			}
			return lower_case_prefix;
		}

		private static string get_ccode_lower_case_suffix (Vala.Symbol sym) {
			var ccode = sym.get_attribute ("CCode");
			string lower_case_suffix = null;

			if (ccode != null) {
				lower_case_suffix = ccode.get_string ("lower_case_csuffix");
			}
			if (lower_case_suffix == null) {
				if (sym is Vala.ObjectTypeSymbol) {
					var csuffix = Vala.Symbol.camel_case_to_lower_case (sym.name);
					// remove underscores in some cases to avoid conflicts of type macros
					if (csuffix.has_prefix ("type_")) {
						csuffix = "type" + csuffix.substring ("type_".length);
					} else if (csuffix.has_prefix ("is_")) {
						csuffix = "is" + csuffix.substring ("is_".length);
					}
					if (csuffix.has_suffix ("_class")) {
						csuffix = csuffix.substring (0, csuffix.length - "_class".length) + "class";
					}
					lower_case_suffix = csuffix;
				} else if (sym.name != null) {
					lower_case_suffix = Vala.Symbol.camel_case_to_lower_case (sym.name);
				}
			}
			return lower_case_suffix;
		}		
		
	}
}