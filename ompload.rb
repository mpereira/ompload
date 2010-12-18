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

  class ThrottledError < StandardError; end

  module CLI
    extend self

    def curl_installed?
      !%x{curl --version 2> /dev/null}.empty?
    end

    def xclip_installed?
      !%x{which xclip 2> /dev/null}.empty?
    end

    def upload_with_curl(file_path, options = {})
      response = Tempfile.new('ompload')
      progress_bar_or_silent = options[:silent] ? '-s' : '-#'
      %x{curl #{progress_bar_or_silent} -F file1=@#{file_path.inspect} #{Omploader::UPLOAD_URL} -o '#{response.path}'}
      IO.read(response.path)
    end

    def handle_file_upload(file_path)
      puts "Progress for '#{file_path}'" unless @options[:quiet]
      response = upload_with_curl(file_path, :silent => @options[:quiet])

      if response =~ /Slow down there, cowboy\./
        raise ThrottledError
      else
        if response =~ /View file: <a href="v([A-Za-z0-9+\/]+)">/
          puts "Omploaded '#{file_path}' to #{Omploader.file_url($1)}" unless @options[:quiet]
          if xclip_installed? && @options[:clip]
            @xclip_buffer += "#{Omploader.file_url(id)}\n"
          end
        else
          STDERR.puts "Error omploading '#{file_path}'"
          @errors += 1
        end
      end
    rescue ThrottledError
      STDERR.puts "Got throttled when trying to ompload '#{file_path}'"
      STDERR.puts "Increasing wait and attempting to continue..."
      sleep 60 and retry
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
          handle_file_upload(file_path)
        end
      end
    end

    def run(argv, options = {})
      @argv = argv.dup
      @options = options

      unless curl_installed?
        abort('Error: curl missing or not in path. Cannot continue.')
      end

      if ARGV.size < 1 || options[:help]
        abort(USAGE)
      end

      @errors = 0
      @xclip_buffer = ''

      upload_files_from_argv if ARGV.size > 0

      if xclip_installed? && options[:clip] && !@xclip_buffer.empty?
        IO.popen('xclip', 'w+').puts @xclip_buffer
      end

      unless options[:quiet]
        puts @errors > 0 ? "Finished with #{@errors} errors." : 'Success.'
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
