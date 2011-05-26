# ompload

CLI to upload files to [omploader](http://ompldr.org).

## Dependencies
`ompload` requires a copy of [cURL](http://curl.haxx.se) in the PATH, and will
automatically copy the list of URLs to the X11 clipboard if
[xclip](http://sourceforge.net/projects/xclip) is available in your PATH.

## Install
    $ gem install ompload

## Usage
    $ ompload [-h|--help] [options] [file(s)]
      -q, --quiet     Only output errors and warnings
      -u, --url       Only output URLs
      -f, --filename  File name on omploader for when piping data via stdin
      -n, --no-clip   Disable copying of the URL to the clipboard

      You can supply a list of files or data via stdin (or both)

### Omploading regular files
    $ ompload foo bar baz

### Omploading data from stdin and giving it a name on [omploader](http://ompldr.org)
    $ echo 'qux' | ompload -f qux

## Author
[Murilo Pereira](http://murilopereira.com)

## License
Distributed under the terms of the GNU General Public License v3

## [Original project](http://git.omp.am/?p=omploader.git;a=blob;f=ompload;hb=HEAD)
    Copyright 2007-2009 David Shakaryan <omp@gentoo.org>
    Copyright 2007-2009 Brenden Matthews <brenden@diddyinc.com>
    Distributed under the terms of the GNU General Public License v3
    Special thanks to Christoph for a patch.
