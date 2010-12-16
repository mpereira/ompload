#!/usr/bin/env ruby
#
# Copyright 2007-2009 David Shakaryan <omp@gentoo.org>
# Copyright 2007-2009 Brenden Matthews <brenden@diddyinc.com>
#
# Distributed under the terms of the GNU General Public License v3
#
# Special thanks to Christoph for a patch.
#

require 'getoptlong'
require 'tempfile'
require 'iconv'

module Omploader
  URL = 'http://ompldr.org/'
  MAX_FILE_SIZE = 2**30
end

quiet = false
url_only = false
help = false
filename = 'pasta'
want_xclip = true
xclip_buf = ''

# Pipe?
begin
  stdin = STDIN.read(4096)
rescue Errno::EAGAIN
  # We just ignore this
end

opts = GetoptLong.new([ '--help',     '-h', GetoptLong::NO_ARGUMENT       ],
                      [ '--filename', '-f', GetoptLong::REQUIRED_ARGUMENT ],
                      [ '--quiet',    '-q', GetoptLong::NO_ARGUMENT       ],
                      [ '--url',      '-u', GetoptLong::NO_ARGUMENT       ],
                      [ '--no-clip',  '-n', GetoptLong::NO_ARGUMENT       ])

opts.each do |opt, arg|
  case opt
  when '--help'
    help = true
  when '--filename'
    filename = arg
  when '--quiet'
    quiet = true
  when '--url'
    url_only = true
  when '--no-clip'
    want_xclip = false
  end
end

argv = ARGV.dup

nocurl = false
curl = %x{curl --version 2> /dev/null}
if curl.empty?
  nocurl = true
  STDERR.puts 'Error: curl missing or not in path.  Cannot continue.'
  STDERR.puts
end

xclip = %x{which xclip 2> /dev/null}
if xclip.empty?
  want_xclip = false
end

if (ARGV.size < 1 && (stdin.nil? || stdin.empty?)) || help || nocurl
  STDERR.puts 'Usage:  ompload [-h|--help] [options] [file(s)]'
  STDERR.puts '  -q, --quiet     Only output errors and warnings'
  STDERR.puts '  -u, --url       Only output URL when finished'
  STDERR.puts '  -f, --filename  Filename to use when posting data'
  STDERR.puts '                  from stdin'
  STDERR.puts '  -n, --no-clip   Disable copying of URL to clipboard'
  STDERR.puts '                  (this feature uses the xclip tool)'
  STDERR.puts
  STDERR.puts '  You can supply a list of files or data via stdin (or both)'
  STDERR.puts
  STDERR.puts '  This script requires a copy of cURL in the path,'
  STDERR.puts '  and will automatically copy the list of URLs to.'
  STDERR.puts '  the X11 clipboard if the `xclip\' program is'
  STDERR.puts '  available in your PATH.'
  Process.exit
end

errors = 0

wait = 5

used_stdin = false
first = true

argv.each do |arg|
  if stdin.nil? && !used_stdin && !File.file?(arg)
    STDERR.puts "Invalid argument '#{arg}': file does not exist (or is not a regular file)."
    errors += 1
    next
  elsif !arg.empty? && File.size(arg) > Omploader::MAX_FILE_SIZE
    STDERR.puts "Error omploading '#{arg}': file exceeds " + (Omploader::MAX_FILE_SIZE).to_s + " bytes (size was " + File.size(arg).to_s + ")."
    errors += 1
    next
  end

  if !first
    # try not to hammer the server
    puts 'Sleeping for ' + wait.to_s + 's' if !quiet && !url_only
    sleep(wait)
  else
    first = false
  end

  tmp = Tempfile.new(filename)
  if !stdin.nil? && !used_stdin
    # upload from stdin
    puts "Progress for '#{arg}'" if !quiet && !url_only
    if quiet || url_only
      p = IO.popen("curl -s -F 'file1=@-;filename=\"#{filename}\"' #{Omploader::URL}upload -o '#{tmp.path}'", "w+")
    else
      p = IO.popen("curl -# -F 'file1=@-;filename=\"#{filename}\"' #{Omploader::URL}upload -o '#{tmp.path}'", "w+")
    end
    p.puts stdin
    p.close_write
    Process.wait
    used_stdin = true
  else
    # upload file
    puts "Progress for '#{arg}'" if !quiet && !url_only
    # escape quotes
    tmp_path = arg.gsub('"', '\"')
    if quiet || url_only
      %x{curl -s -F file1=@"#{tmp_path}" #{Omploader::URL}upload -o '#{tmp.path}'}
    else
      %x{curl -# -F file1=@"#{tmp_path}" #{Omploader::URL}upload -o '#{tmp.path}'}
    end
  end
  if !File.size?(tmp.path)
    STDERR.puts "Error omploading '#{arg}'"
    errors += 1
    next
  end
  output = IO.read(tmp.path)
  output = Iconv.conv('ASCII//IGNORE//TRANSLIT', 'UTF-8', output)

  # parse for an ID
  if output =~ /View file: <a href="v([A-Za-z0-9+\/]+)">/
    id = $1
    puts "Omploaded '#{arg}' to #{Omploader::URL}v#{id}" if !quiet
    xclip_buf += "#{Omploader::URL}v#{id}\n" unless !want_xclip
    wait = 5
  elsif output =~ /Slow down there, cowboy\./
    wait += 60
    argv << arg
    STDERR.puts "Got throttled when trying to ompload '#{arg}'"
    STDERR.puts "Increasing wait and attempting to continue..."
    errors += 1
  else
    STDERR.puts "Error omploading '#{arg}'"
    errors += 1
  end

end

if want_xclip && !xclip_buf.empty?
  p = IO.popen("xclip", "w+")
  p.puts xclip_buf
end

if !quiet && !url_only
  if errors < 1
    puts "Success."
  else
    puts "Finished with #{errors} errors."
  end
end
