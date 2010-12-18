#!/usr/bin/env ruby
#
# Copyright 2007-2009 David Shakaryan <omp@gentoo.org>
# Copyright 2007-2009 Brenden Matthews <brenden@diddyinc.com>
#
# Distributed under the terms of the GNU General Public License v3
#
# Special thanks to Christoph for a patch.
#

require 'singleton'
require 'getoptlong'
require 'tempfile'
require 'iconv'

class XclipBuffer
  include Singleton

  attr_reader :content

  def initialize
    @content = ''
  end

  def append!(string)
    @content += "#{string}\n"
  end
end

class ErrorCounter
  include Singleton

  attr_reader :count

  def initialize
    @count = 0
  end

  def increment!
    @count += 1
  end
end

module Shell
  def curl_installed?
    !%x{curl --version 2> /dev/null}.empty?
  end

  def xclip_installed?
    !%x{which xclip 2> /dev/null}.empty?
  end
end

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
      the X11 clipboard if the `xclip' program is
      available in your PATH.
  USAGE

  class ThrottledError < StandardError; end

  module Message
    extend self

    def curl_failed_posting_file(file_path)
      "error: curl failed to return a response uploading '#{file_path}'"
    end

    def throttled(file_path)
      "error: got throttled when trying to ompload '#{file_path}'\n" <<
      "Awaiting 60s and attempting to continue..."
    end

    def progress(file_path)
      "Progress for '#{file_path}'"
    end

    def omploaded(file_path, id)
      "Omploaded '#{file_path}' to #{Omploader.file_url(id)}"
    end

    def invalid_file(file_path)
      "error: '#{file_path}' does not exist or is not a regular file"
    end

    def file_too_big(file_path)
      "error: '#{file_path}' exceeds #{MAX_FILE_SIZE} bytes " <<
      "(size is #{File.size(file_path)})."
    end
  end

  module UploadsHandler
    extend self, Shell

    def handle(file_paths, options = {})
      file_paths.each do |file_path|
        if !File.file?(file_path)
          STDERR.puts Message.invalid_file(file_path)
          ErrorCounter.instance.increment!
        elsif File.size(file_path) > MAX_FILE_SIZE
          STDERR.puts Message.file_too_big(file_path)
          ErrorCounter.instance.increment!
        else
          handle_file(file_path, options)
        end
      end
    end

    private

    def upload_with_curl(file_path, options = {})
      response = Tempfile.new('ompload')
      progress_bar_or_silent = options[:silent] ? '-s' : '-#'
      %x{curl #{progress_bar_or_silent} -F file1=@#{file_path.inspect} #{Omploader::UPLOAD_URL} -o '#{response.path}'}
      IO.read(response.path)
    end

    def handle_file(file_path, options = {})
      puts Message.progress(file_path) unless options[:quiet]
      response = upload_with_curl(file_path, :silent => options[:quiet])

      if response =~ /Slow down there, cowboy\./
        raise ThrottledError
      else
        if response =~ /View file: <a href="v([A-Za-z0-9+\/]+)">/
          puts Message.omploaded(file_path, $1) unless options[:quiet]
          if xclip_installed? && options[:clip]
            XclipBuffer.instance.append!("#{Omploader.file_url($1)}")
          end
        else
          STDERR.puts Message.curl_failed_posting_file(file_path)
          ErrorCounter.instance.increment!
        end
      end
    rescue ThrottledError
      STDERR.puts Message.throttled(file_path)
      sleep(60) and retry
    end
  end

  module CLI
    extend self, Shell

    def run(argv, options = {})
      unless curl_installed?
        abort('error: curl missing or not in path. Cannot continue.')
      end

      abort(USAGE) if ARGV.size < 1 || options[:help]

      UploadsHandler.handle(argv, options) if ARGV.size > 0

      if xclip_installed? && options[:clip] && !XclipBuffer.instance.content.empty?
        IO.popen('xclip', 'w+').puts XclipBuffer.instance.content
      end

      unless options[:quiet]
        if ErrorCounter.instance.count > 0
          puts "Finished with #{ErrorCounter.instance.count} errors."
        else
          puts 'Success.'
        end
      end
    end
  end
end

opts = GetoptLong.new(['--help',    '-h', GetoptLong::NO_ARGUMENT],
                      ['--quiet',   '-q', GetoptLong::NO_ARGUMENT],
                      ['--no-clip', '-n', GetoptLong::NO_ARGUMENT])

options = { :clip => true }

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
