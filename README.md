## PEDSnet::Lessidentify

`PEDSnet::Lessidentify` proivides a set of tools to reduce some risks to privacy in datasets that describe individual persons.  Its goal is to strike a reasonable balance between reducing privacy risk and creating complexity in order to address risks that may need to be handled through data sharing agreements rather than data obfuscation.

`PEDSnet::Lessidentify` is implemented as a [Perl5](http://www.perl.org) package with the goal of portability, given the wide installed base for Perl5.  Consistent with this goal, we've made an effort to avoid use of code beyond base Perl that requires a C compiler or specific binaries, and have stuck to pure-Perl implementation.  This comes at some performance cost, which we hope is reasonable in light of the fact that lessidentification is usually a small part of the process of assembling a dataset for sharing, and inefficiency here is less likely to be rate-limiting.

For more information on what's in the box, see the [SYNOPSIS.md](SYNOPSIS.md) file in the repository, or `perldoc PEDSnet::Lessidentify` after installing the module.


### Rules of the Road

We are strong believers in open, collaborative science, and we've made PEDSnet::Lessidentify available as open-source software in that mindset.  Knowing that people get very anxious about tools that may affect privacy risk (appropriately so - this is important stuff), we also wanted to point anyone with questions to the terms of use.  These are detailed in the [LICENSE](LICENSE) file that accompanies the distribution, which in a nutshell presents the GPL and Artistic licenses.  Of particular note, both licenses contain disclaimers of warranty and liability following standard open-source practice.  Caveat utor.

### Installing PEDSnet::Lessidentify

Fundamentally, PEDSnet::Lessidentify is installed like any other Perl module.  If you're not already familiar with Perl module management, you may find one of these options useful.

#### Existing Perl5 Installation

If you have a recent version (5.24 or later) of Perl installed, you have several options for adding this package:

```
# Interactive package installer distributed with Perl
cpan PEDSnet::Lessidentify
# cpanminus - released version
cpanm PEDSnet::Lessidentify
# cpanminus - current development version
cpanm https://github.com/PEDSnet/PEDSnet-Lessidentify
```

#### New Perl5 Installation

If you don't have a current version of Perl, or would like to avoid messing with the system's installed version, you can install a fresh copy of Perl and work with it instead.  On Unix-like systems with a C compiler, the following recipe will do the trick:

```
# Use perlbrew to manage local versions of Perl
curl -L https://install.perlbrew.pl | bash
perlbrew init
# Build a new perl version; see perlbrew available for options
perlbrew install perl-stable
perlbrew install-cpanm
# Install PEDSnet::Lessidentify
cpanm PEDSnet::Lessidentify
# OR, if you want the bleeding edge
cpanm https://github.com/PEDSnet/PEDSnet-Lessidentify
```

If building from source isn't an option for you, visit http://www.perl.org/get.html for binary versions, each of which comes with a package manager that should let you add on the released version of `PEDSnet::Lessidentify`.

#### Docker Container

Finally, if you want to avoid the overhead of building Perl, or prefer to keep PEDSnet::Lessidentify separated, you can use this [Dockerfile](etc/Dockerfile) or one like it build a Docker image that includes PEDSnet::Lessidentify.
