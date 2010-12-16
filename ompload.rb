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
end

module Ompload
  MAX_FILE_SIZE = 2**30

  module CLI
    extend self

    USAGE = <<-USAGE.gsub(/^      /, '')
      Usage:  ompload [-h|--help] [options] [file(s)]
        -q, --quiet     Only output errors and warnings
        -u, --url       Only output URL when finished
        -f, --filename  Filename to use when posting data
                        from stdin
        -n, --no-clip   Disable copying of URL to clipboard
                        (this feature uses the xclip tool)

        You can supply a list of files or data via stdin (or both)

        This script requires a copy of cURL in the path,
        and will automatically copy the list of URLs to.
        the X11 clipboard if the `xclip\ program is
        available in your PATH.
    USAGE

    def curl_installed?
      !%x{curl --version 2> /dev/null}.empty?
    end

    def xclip_installed?
      !%x{which xclip 2> /dev/null}.empty?
    end

    def run(argv, options = {})
      @argv = argv.dup
      @options = options

      # Pipe?
      begin
        stdin = STDIN.read_nonblock(4096)
      rescue Errno::EAGAIN
        # We just ignore this
      end

      unless curl_installed?
        abort('Error: curl missing or not in path. Cannot continue.')
      end

      options[:clip] = false unless xclip_installed?

      if (ARGV.size < 1 && (stdin.nil? || stdin.empty?)) || options[:help]
        STDERR.puts USAGE
        Process.exit
      end

      errors = 0

      wait = 5

      used_stdin = false
      first = true
      xclip_buf = ''

      @argv.each do |arg|
        if stdin.nil? && !used_stdin && !File.file?(arg)
          STDERR.puts "Invalid argument '#{arg}': file does not exist (or is not a regular file)."
          errors += 1
          next
        elsif !arg.empty? && File.size(arg) > Ompload::MAX_FILE_SIZE
          STDERR.puts "Error omploading '#{arg}': file exceeds " + (Ompload::MAX_FILE_SIZE).to_s + " bytes (size was " + File.size(arg).to_s + ")."
          errors += 1
          next
        end

        if !first
          # try not to hammer the server
          puts 'Sleeping for ' + wait.to_s + 's' if !options[:quiet] && !options[:url]
          sleep(wait)
        else
          first = false
        end

        tmp = Tempfile.new(options[:filename])
        if !stdin.nil? && !used_stdin
          # upload from stdin
          puts "Progress for '#{arg}'" if !options[:quiet] && !options[:url]
          if options[:quiet] || options[:url]
            p = IO.popen("curl -s -F 'file1=@-;filename=\"#{options[:filename]}\"' #{Omploader::URL}upload -o '#{tmp.path}'", "w+")
          else
            p = IO.popen("curl -# -F 'file1=@-;filename=\"#{options[:filename]}\"' #{Omploader::URL}upload -o '#{tmp.path}'", "w+")
          end
          p.puts stdin
          p.close_write
          Process.wait
          used_stdin = true
        else
          # upload file
          puts "Progress for '#{arg}'" if !options[:quiet] && !options[:url]
          # escape quotes
          tmp_path = arg.gsub('"', '\"')
          if options[:quiet] || options[:url]
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
          puts "Omploaded '#{arg}' to #{Omploader::URL}v#{id}" if !options[:quiet]
          xclip_buf += "#{Omploader::URL}v#{id}\n" unless !options[:clip]
          wait = 5
        elsif output =~ /Slow down there, cowboy\./
          wait += 60
          @argv << arg
          STDERR.puts "Got throttled when trying to ompload '#{arg}'"
          STDERR.puts "Increasing wait and attempting to continue..."
          errors += 1
        else
          STDERR.puts "Error omploading '#{arg}'"
          errors += 1
        end
      end

      if options[:clip] && !xclip_buf.empty?
        p = IO.popen("xclip", "w+")
        p.puts xclip_buf
      end

      if !options[:quiet] && !options[:url]
        if errors < 1
          puts "Success."
        else
          puts "Finished with #{errors} errors."
        end
      end
    end
  end
end

opts = GetoptLong.new(['--help',     '-h', GetoptLong::NO_ARGUMENT       ],
                      ['--filename', '-f', GetoptLong::REQUIRED_ARGUMENT ],
                      ['--quiet',    '-q', GetoptLong::NO_ARGUMENT       ],
                      ['--url',      '-u', GetoptLong::NO_ARGUMENT       ],
                      ['--no-clip',  '-n', GetoptLong::NO_ARGUMENT       ])

options = {}
options[:filename] = 'pasta'

opts.each do |opt, arg|
  case opt
  when '--help'
    options[:help] = true
  when '--filename'
    options[:filename] = arg
  when '--quiet'
    options[:quiet] = true
  when '--url'
    options[:url] = true
  when '--no-clip'
    options[:clip] = false
  end
end

Ompload::CLI.run(ARGV, options) if $0 == __FILE__
