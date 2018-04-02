
use strict;
use warnings;

use Module::Build 0.28;


my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.28"
  },
  "configure_requires" => {
    "ExtUtils::MakeMaker" => 0,
    "Module::Build" => "0.28"
  },
  "dist_abstract" => "Make it harder to identifiy individuals in a dataset",
  "dist_author" => [
    "Charles Bailey <cbail\@cpan.org>"
  ],
  "dist_name" => "PEDSnet-Lessidentify",
  "dist_version" => "1.51",
  "license" => "open_source",
  "module_name" => "PEDSnet::Lessidentify",
  "recursive_test_files" => 1,
  "requires" => {
    "Carp" => 0,
    "Data::Record" => 0,
    "DateTime" => 0,
    "JSON::MaybeXS" => 0,
    "Math::Random" => 0,
    "Math::Random::Secure" => 0,
    "Module::Runtime" => 0,
    "Moo" => 2,
    "MooX::ConfigFromFile" => 0,
    "MooX::Options" => 0,
    "MooX::Role::Chatty" => 0,
    "Path::Tiny" => 0,
    "Regexp::Common" => 0,
    "Rose::DateTime::Util" => 0,
    "Text::CSV" => 0,
    "Types::Standard" => 0,
    "experimental" => 0,
    "perl" => "5.024",
    "strict" => 0,
    "warnings" => 0
  },
  "script_files" => [
    "script/scrub_csv"
  ],
  "test_requires" => {
    "ExtUtils::MakeMaker" => 0,
    "File::Spec" => 0,
    "FindBin" => 0,
    "Log::Any::Adapter::Carp" => 0,
    "Test::More" => 0
  }
);


my %fallback_build_requires = (
  "ExtUtils::MakeMaker" => 0,
  "File::Spec" => 0,
  "FindBin" => 0,
  "Log::Any::Adapter::Carp" => 0,
  "Module::Build" => "0.28",
  "Test::More" => 0
);


unless ( eval { Module::Build->VERSION(0.4004) } ) {
  delete $module_build_args{test_requires};
  $module_build_args{build_requires} = \%fallback_build_requires;
}

my $build = Module::Build->new(%module_build_args);


$build->create_build_script;
