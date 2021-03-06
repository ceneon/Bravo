# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{bravo}
  s.version = "0.4.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Leandro Marcucci"]
  s.date = %q{2011-03-21}
  s.description = %q{Adaptador para el Web Service de Facturacion Electronica de AFIP}
  s.email = %q{leanucci@vurbia.com}
  s.extra_rdoc_files = [
    "LICENSE.txt",
    "README.textile"
  ]
  s.files = [
    ".document",
    "CHANGELOG",
    "Gemfile",
    "Gemfile.lock",
    "LICENSE.txt",
    "README.textile",
    "Rakefile",
    "VERSION",
    "autotest/discover.rb",
    "bravo.gemspec",
    "lib/bravo.rb",
    "lib/bravo/auth_data.rb",
    "lib/bravo/authorizer.rb",
    "lib/bravo/bill.rb",
    "lib/bravo/constants.rb",
    "lib/bravo/core_ext/float.rb",
    "lib/bravo/core_ext/hash.rb",
    "lib/bravo/core_ext/string.rb",
    "lib/bravo/version.rb",
    "spec/bravo/auth_data_spec.rb",
    "spec/bravo/authorizer_spec.rb",
    "spec/bravo/bill_spec.rb",
    "spec/spec_helper.rb",
    "wsaa-client.sh"
  ]
  s.homepage = %q{http://github.com/Vurbia/Bravo}
  s.licenses = ["MIT"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.6.1}
  s.summary = %q{Adaptador AFIP wsfe.}
  s.test_files = [
    "spec/bravo/auth_data_spec.rb",
    "spec/bravo/authorizer_spec.rb",
    "spec/bravo/bill_spec.rb",
    "spec/spec_helper.rb"
  ]

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<savon>, ["= 1.2.0"])
      s.add_development_dependency(%q<ruby-debug>, [">= 0"])
      s.add_development_dependency(%q<ruby-debug-base19>, ["= 0.11.24"])
      s.add_development_dependency(%q<ruby-debug19>, ["= 0.11.6"])
      s.add_development_dependency(%q<rspec>, ["~> 2.4.0"])
      s.add_development_dependency(%q<bundler>, ["~> 1.0.0"])
      s.add_development_dependency(%q<jeweler>, ["~> 1.5.1"])
      s.add_development_dependency(%q<rcov>, [">= 0"])
    else
      s.add_dependency(%q<savon>, ["= 1.2.0"])
      s.add_dependency(%q<ruby-debug>, [">= 0"])
      s.add_dependency(%q<ruby-debug-base19>, ["= 0.11.24"])
      s.add_dependency(%q<ruby-debug19>, ["= 0.11.6"])
      s.add_dependency(%q<rspec>, ["~> 2.4.0"])
      s.add_dependency(%q<bundler>, ["~> 1.0.0"])
      s.add_dependency(%q<jeweler>, ["~> 1.5.1"])
      s.add_dependency(%q<rcov>, [">= 0"])
    end
  else
    s.add_dependency(%q<savon>, ["= 1.2.0"])
    s.add_dependency(%q<ruby-debug>, [">= 0"])
    s.add_dependency(%q<ruby-debug-base19>, ["= 0.11.24"])
    s.add_dependency(%q<ruby-debug19>, ["= 0.11.6"])
    s.add_dependency(%q<rspec>, ["~> 2.4.0"])
    s.add_dependency(%q<bundler>, ["~> 1.0.0"])
    s.add_dependency(%q<jeweler>, ["~> 1.5.1"])
    s.add_dependency(%q<rcov>, [">= 0"])
  end
end

