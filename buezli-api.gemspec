require_relative "lib/buezli/api/version"

Gem::Specification.new do |spec|
  spec.name = "buezli-api"
  spec.version = Buezli::Api::VERSION
  spec.summary = "Schema-driven Ruby client for the Buezli API"
  spec.description = "A read-only Ruby client generated from Buezli's versioned API schema."
  spec.authors = [ "Codegestalt" ]
  spec.license = "MIT"
  spec.homepage = "https://buezli.app/api"
  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb", "schemas/**/*.json", "LICENSE", "README.md"] }
  spec.require_paths = [ "lib" ]
  spec.required_ruby_version = ">= 3.2"
  spec.metadata["source_code_uri"] = "https://github.com/codegestalt/buezli-api"
  spec.metadata["documentation_uri"] = "https://buezli.app/api"
  spec.metadata["bug_tracker_uri"] = "https://github.com/codegestalt/buezli-api/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.add_dependency "activesupport", ">= 7.2", "< 9"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
