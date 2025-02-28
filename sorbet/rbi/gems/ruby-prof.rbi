# This file is autogenerated. Do not edit it by hand. Regenerate it with:
#   srb rbi gems

# typed: strict
#
# If you would like to make changes to this file, great! Please create the gem's shim here:
#
#   https://github.com/sorbet/sorbet-typed/new/master?filename=lib/ruby-prof/all/ruby-prof.rbi
#
# ruby-prof-1.4.3

class RubyProf::Allocation
  def _dump_data; end
  def _load_data(arg0); end
  def count; end
  def klass_flags; end
  def klass_name; end
  def line; end
  def memory; end
  def source_file; end
end
class RubyProf::CallTree
  def <=>(other); end
  def _dump_data; end
  def _load_data(arg0); end
  def called; end
  def children; end
  def children_time; end
  def depth; end
  def inspect; end
  def line; end
  def measurement; end
  def parent; end
  def self_time; end
  def source_file; end
  def target; end
  def to_s; end
  def total_time; end
  def wait_time; end
end
class RubyProf::CallTrees
  def _dump_data; end
  def _load_data(arg0); end
  def call_trees; end
  def callees; end
  def callers; end
  def min_depth; end
end
class RubyProf::Measurement
  def _dump_data; end
  def _load_data(arg0); end
  def called; end
  def called=(arg0); end
  def children_time; end
  def inspect; end
  def self_time; end
  def to_s; end
  def total_time; end
  def wait_time; end
end
class RubyProf::MethodInfo
  def <=>(other); end
  def _dump_data; end
  def _load_data(arg0); end
  def allocations; end
  def call_trees; end
  def called; end
  def children_time; end
  def full_name; end
  def klass_flags; end
  def klass_name; end
  def line; end
  def measurement; end
  def method_name; end
  def recursive?; end
  def self_time; end
  def source_file; end
  def to_s; end
  def total_time; end
  def wait_time; end
  include Comparable
end
class RubyProf::Profile
  def _dump_data; end
  def _load_data(arg0); end
  def exclude_common_methods!; end
  def exclude_method!(arg0, arg1); end
  def exclude_methods!(mod, *method_or_methods); end
  def exclude_singleton_methods!(mod, *method_or_methods); end
  def initialize(*arg0); end
  def measure_mode; end
  def measure_mode_string; end
  def pause; end
  def paused?; end
  def profile; end
  def resume; end
  def running?; end
  def self.profile(*arg0); end
  def start; end
  def stop; end
  def threads; end
  def track_allocations?; end
end
class RubyProf::Thread
  def _dump_data; end
  def _load_data(arg0); end
  def call_tree; end
  def fiber_id; end
  def id; end
  def methods; end
  def total_time; end
  def wait_time; end
end
module RubyProf
  def self.ensure_not_running!; end
  def self.ensure_running!; end
  def self.exclude_threads; end
  def self.exclude_threads=(value); end
  def self.figure_measure_mode; end
  def self.measure_mode; end
  def self.measure_mode=(value); end
  def self.pause; end
  def self.profile(options = nil, &block); end
  def self.resume; end
  def self.running?; end
  def self.start; end
  def self.start_script(script); end
  def self.stop; end
end
module RubyProf::ExcludeCommonMethods
  def self.apply!(profile); end
  def self.exclude_enumerable(profile, mod, *method_or_methods); end
  def self.exclude_methods(profile, mod, *method_or_methods); end
  def self.exclude_singleton_methods(profile, mod, *method_or_methods); end
end
module Rack
end
class Rack::RubyProf
  def call(env); end
  def initialize(app, options = nil); end
  def paths_match?(path, paths); end
  def print(data, path); end
  def profiling_options; end
  def should_profile?(path); end
end
class RubyProf::AbstractPrinter
  def filter_by; end
  def initialize(result); end
  def max_percent; end
  def method_href(thread, method); end
  def method_location(method); end
  def min_percent; end
  def open_asset(file); end
  def print(output = nil, options = nil); end
  def print_column_headers; end
  def print_footer(thread); end
  def print_header(thread); end
  def print_thread(thread); end
  def print_threads; end
  def self.needs_dir?; end
  def setup_options(options = nil); end
  def sort_method; end
  def time_format; end
end
