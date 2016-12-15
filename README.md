# [AIscm][1]

[![GPLv3](https://img.shields.io/github/license/wedesoft/aiscm.png)](https://www.gnu.org/copyleft/gpl.html) [![Travis CI](https://travis-ci.org/wedesoft/aiscm.png?branch=master)](https://travis-ci.org/wedesoft/aiscm) [![GitHub](https://img.shields.io/github/release/wedesoft/aiscm.png)](https://github.com/wedesoft/aiscm/releases) [![Guile 2.0.11](http://img.shields.io/badge/Guile-2.0.11-yellow.png)](http://www.gnu.org/software/guile) [![amd64](http://img.shields.io/badge/architecture-amd64-lightgrey.png)](https://en.wikipedia.org/wiki/X86-64) [![DOI](https://zenodo.org/badge/15473832.svg)](https://zenodo.org/badge/latestdoi/15473832)

[**AIscm**][1] is a **[Guile][2] extension for numerical arrays and tensors**.
Performance is achieved by means of a JIT compiler.

Control all data and machine code down to every single bit and byte!

![AIscm](doc/aiscm.gif "AIscm")

## Download

You can download the current state of the software like this:

```Shell
git clone git@github.com:wedesoft/aiscm.git
cd aiscm
```

## Dependencies

You can install the dependencies as follows:

```Shell
sudo apt-get install -q --yes build-essential autoconf automake libtool devscripts equivs
sudo mk-build-deps --install --remove --tool 'apt-get -q --yes' debian/control
```

## Installation

Finally you can install the software as follows

```Shell
./bootstrap
./configure
make -j
make check -j
sudo make install
cd ..
```

## Run tests

### Unit tests

You can run all tests like this

```Shell
make check -j
```

One can use *recheck* to run only the test suites which have not completed successfully:

```Shell
make recheck -j
```

To run a single test suite, you can delete the *log* file and regenerate it using *make*:

```Shell
cd tests
rm -f test_asm.log && make test_asm.log
cd ..
```

### Integration tests

Running the integration tests requires a graphical display, keyboard interaction, a camera, and a sound device.

```Shell
make integration
```

One can use *reintegration* to run only the integration tests which have not completed successfully:

```Shell
make reintegration
```

# See also

* [AIscm homepage][1]
* [AIscm installation][6]
* [Debian sbuild[3] (installed from jessie-backports because of [bug 827315][7])
* [Docker][4]
* [managing Debian packages][5]

[1]: http://wedesoft.github.io/aiscm/ "AIscm"
[2]: http://www.gnu.org/software/guile/ "Guile programming language"
[3]: https://wiki.debian.org/sbuild
[4]: https://www.docker.com/
[5]: https://www.debian.org/doc/manuals/developers-reference/ch05.en.html#newpackage
[6]: http://wedesoft.github.io/aiscm/installation.html "AIscm installation"
[7]: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=827315
