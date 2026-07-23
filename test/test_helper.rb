require "bundler/setup"
require "json"
require "pathname"

BUEZLI_API_ROOT = Pathname(__dir__).join("..").expand_path
$LOAD_PATH.unshift BUEZLI_API_ROOT.join("lib").to_s

require "minitest/autorun"
require "active_support"
require "active_support/test_case"
require "active_support/core_ext/object/deep_dup"
require "buezli/api"
