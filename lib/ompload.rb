require 'singleton'
require 'tempfile'

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

  def piped_data_given?
    !STDIN.tty?
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
  VERSION = '1.0.2'
  MAX_FILE_SIZE = 2**20

  USAGE = <<-USAGE.gsub(/^    /, '')
    Usage: ompload [-h|--help] [options] [file(s)]
      -q, --quiet     Only output errors and warnings
      -u, --url       Only output URLs
      -f, --filename  File name on omploader for when piping data via stdin
      -n, --no-clip   Disable copying of the URL to the clipboard
      -v, --version   Show version

      You can supply a list of files or data via stdin (or both)
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

    def payload_too_big(file_path, file_size)
      "error: '#{file_path}' exceeds #{MAX_FILE_SIZE} bytes " <<
      "(size is #{file_size})."
    end
  end

  module UploadsHandler
    extend self, Shell

    def handle_file(file_path, options = {})
      puts Message.progress(file_path) if !options[:quiet] && !options[:url]
      response = upload_with_curl({ :file_path => file_path,
                                    :silent => options[:quiet] || options[:url] })
      handle_response!(response, file_path, options)
    rescue ThrottledError
      STDERR.puts Message.throttled(file_path)
      sleep(60) and retry
    end

    def handle_files(file_paths, options = {})
      file_paths.each do |file_path|
        if !File.file?(file_path)
          STDERR.puts Message.invalid_file(file_path)
          ErrorCounter.instance.increment!
        elsif File.size(file_path) > MAX_FILE_SIZE
          STDERR.puts Message.payload_too_big(file_path,File.size(file_path))
          ErrorCounter.instance.increment!
        else
          handle_file(file_path, options)
        end
      end
    end

    def handle_data(data, options = {})
      file_name = options[:file_name] || 'piped data'
      if data.bytesize > MAX_FILE_SIZE
          STDERR.puts Message.payload_too_big(file_name, data.bytesize)
          ErrorCounter.instance.increment!
      else
          puts Message.progress(file_name) if !options[:quiet] && !options[:url]
          response = upload_with_curl({ :data => data,
                                      :file_name => file_name,
                                      :silent => options[:quiet] || options[:url] })
          handle_response!(response, file_name, options)
      end
    rescue ThrottledError
      STDERR.puts Message.throttled(file_name)
      sleep(60) and retry
    end

    private

    def upload_with_curl(options)
      response = Tempfile.new('ompload')
      progress_bar_or_silent = options[:silent] ? '-s' : '-#'

      if options[:data]
        IO.popen("curl #{progress_bar_or_silent} -F 'file1=@-;filename=#{options[:file_name]}' #{Omploader::UPLOAD_URL} -o '#{response.path}'", "w+") do |pipe|
          pipe.puts options[:data]
        end
      elsif options[:file_path]
        %x{curl #{progress_bar_or_silent} -F file1=@#{options[:file_path].inspect} #{Omploader::UPLOAD_URL} -o '#{response.path}'}
      end

      IO.read(response.path)
    end

    def handle_response!(response, file_name, options)
      if response =~ /Slow down there, cowboy\./
        raise ThrottledError
      else
        if response =~ /View file: <a href="v([A-Za-z0-9+\/]+)">/
          puts Message.omploaded(file_name, $1) unless options[:quiet]
          if xclip_installed? && options[:clip]
            XclipBuffer.instance.append!("#{Omploader.file_url($1)}")
          end
        else
          STDERR.puts Message.curl_failed_posting_file(file_name)
          ErrorCounter.instance.increment!
        end
      end
    end
  end

  module CLI
    extend self, Shell

    def run(argv, options = {})
      unless curl_installed?
        abort('error: curl missing or not in path. Cannot continue.')
      end

      if options[:version]
        puts VERSION
        exit
      end

      abort(USAGE) if ARGV.size < 1 && !piped_data_given? || options[:help]

      UploadsHandler.handle_files(ARGV, options)
      UploadsHandler.handle_data(STDIN.read(), options) if piped_data_given?

      if xclip_installed? && options[:clip] && !XclipBuffer.instance.content.empty?
        IO.popen('xclip', 'w+').puts XclipBuffer.instance.content
      end

      if !options[:quiet] && !options[:url]
        if ErrorCounter.instance.count > 0
          puts "Finished with #{ErrorCounter.instance.count} errors."
        else
          puts 'Success.'
        end
      end
    end
  end
end
