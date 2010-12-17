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
  URL = 'http://ompldr.org'
  UPLOAD_URL = "#{URL}/upload"

  extend self

  def file_url(id)
    "#{URL}/v#{id}"
  end
end

module Ompload
  MAX_FILE_SIZE = 2**32

  USAGE = <<-USAGE.gsub(/^    /, '')
    Usage:  ompload [-h|--help] [options] [file(s)]
      -q, --quiet     Only output errors and warnings
      -n, --no-clip   Disable copying of URL to clipboard
                      (this feature uses the xclip tool)

      You can supply a list of files or data via stdin (or both)

      This script requires a copy of cURL in the path,
      and will automatically copy the list of URLs to.
      the X11 clipboard if the `xclip\ program is
      available in your PATH.
  USAGE

  module CLI
    extend self

    def curl_installed?
      !%x{curl --version 2> /dev/null}.empty?
    end

    def xclip_installed?
      !%x{which xclip 2> /dev/null}.empty?
    end

    def upload_file(file_path)
      puts "Progress for '#{file_path}'" unless @options[:quiet]

      response = Tempfile.new('ompload')

      if @options[:quiet]
        %x{curl -s -F file1=@#{file_path.inspect} #{Omploader::UPLOAD_URL} -o '#{response.path}'}
      else
        %x{curl -# -F file1=@#{file_path.inspect} #{Omploader::UPLOAD_URL} -o '#{response.path}'}
      end

      xclip_buf = ''

      if response =~ /Slow down there, cowboy\./
        raise ThrottledError
      else
        if response =~ /View file: <a href="v([A-Za-z0-9+\/]+)">/
          puts "Omploaded '#{file_path}' to #{Omploader.file_url($1)}" unless @options[:quiet]
          xclip_buf += "#{Omploader.file_url(id)}\n" unless !@options[:clip]
        else
          STDERR.puts "Error omploading '#{file_path}'"
          @errors += 1
        end
      end
    end

    def upload_files_from_argv
      @argv.each do |file_path|
        if !File.file?(file_path)
          STDERR.puts "Invalid argument '#{file_path}': file does not exist (or " <<
                      "is not a regular file)."
          @errors += 1
        elsif File.size(file_path) > Ompload::MAX_FILE_SIZE
          STDERR.puts "Error omploading '#{file_path}': file exceeds " <<
                      "#{Ompload::MAX_FILE_SIZE} bytes (size was " <<
                      "#{File.size(file_path)})."
          @errors += 1
        else
          upload_file(file_path)
        end
      end
    end

    def run(argv, options = {})
      @argv = argv.dup
      @options = options

      unless curl_installed?
        abort('Error: curl missing or not in path. Cannot continue.')
      end

      options[:clip] = false unless xclip_installed?

      if ARGV.size < 1 || options[:help]
        abort(USAGE)
      end

      @errors = 0

      upload_files_from_argv if ARGV.size > 0

      if options[:clip] && !xclip_buf.empty?
        p = IO.popen("xclip", "w+")
        p.puts xclip_buf
      end

      if !options[:quiet]
        if @errors < 1
          puts "Success."
        else
          puts "Finished with #{@errors} errors."
        end
      end
    end
  end
end

opts = GetoptLong.new(['--help',    '-h', GetoptLong::NO_ARGUMENT],
                      ['--quiet',   '-q', GetoptLong::NO_ARGUMENT],
                      ['--no-clip', '-n', GetoptLong::NO_ARGUMENT])

options = {}

opts.each do |opt, arg|
  case opt
  when '--help'
    options[:help] = true
  when '--quiet'
    options[:quiet] = true
  when '--no-clip'
    options[:clip] = false
  end
end

Ompload::CLI.run(ARGV, options) if $0 == __FILE__
