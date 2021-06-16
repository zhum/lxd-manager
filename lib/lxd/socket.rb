# frozen_string_literal: true

#require 'json'
require 'socket'

module LXD
  #
  # Class LXD::Socket provides connection to LXD
  #
  # @author Sergey Zhumatiy <serg@parallel.ru>
  #
  class Socket

    #
    # @!attribute [r] socket
    #   @return [String] path to socket
    attr_reader :socket

    #
    # @!attribute [r] status
    #   @return [Integer] HTTP status of last request
    attr_reader :status

    #
    # Constructor
    #
    # @param [Hash] args
    #               :socket - path to socket [/var/snap/lxd/common/lxd/unix.socket]
    #
    def initialize(args={})
      #warn "--- #{args}"
      @socket = args[:socket] || '/var/snap/lxd/common/lxd/unix.socket'
      @debug = args[:debug]
      @conn = nil
    end
    
    #
    # Send data with GET method and get answer
    #
    # @param [String] data data to send (json format)
    # @param [String] path path
    #
    # @return [Bool] true if success
    #
    def get(path)
      send_data(path, nil, 'GET')
    end

    #
    # Send data with POST method and get answer
    #
    # @param [String] path path
    # @param [String] data data to send (json format)
    #
    # @return [Bool] true if success
    #
    def post(path, data)
      send_data(path, data, 'POST')
    end

    #
    # Read and parse to json answer from socket
    #
    #
    # @return [Hash] answer in JSON format
    #
    def get_answer
      status = nil
      length = nil
      loop do
        answer = @conn.readline.chomp
        warn "<< #{answer}" if @debug
        case answer
        when /HTTP\/[0-9.]+ (\d+)/
          status = $1.to_i
        when /Content-Length: (\d+)/
          length = $1.to_i
        when /^$/
          break
        end
      end

      length = length.to_i
      @status = status.to_i
      return {status: 999, original_status: @status, length: length}.to_json if @status < 1 or @status > 399
      JSON.load(@conn.read(length))
    end

    #
    # Send data to LXD and read answer
    #
    # @param [String] path path
    # @param [String] data JSON formatted data to send
    # @param [String] method GET/POST/PUT/...
    #
    # @return [String] answer in JSON format or nil if failed
    #
    def send_data(path, data, method)
      if @conn.nil? || @conn.closed?
        @conn = UNIXSocket.new(@socket)
      end
      raise "Cannot connect to #{@socket}" unless @conn

      full_data = <<-SEND_DATA
#{method} #{path} HTTP/1.1\r
Host: a\r
User-Agent: site-manager/1.0\r
Accept: */*\r
Content-Length: #{data.to_s.length}\r
Content-Type: application/x-www-form-urlencoded\r
\r
#{data}
SEND_DATA

      warn ">> #{full_data}" if @debug
      @conn.write full_data

      answer = get_answer
      op = answer['operation'].to_s
      if op != ''
        #warn "WAIT..."
        answer = wait_operation op
      end
      warn "!! #{answer}" if @debug
      @conn.close
      answer
    end

    def wait_operation op
      @conn.close if @conn && !@conn.closed?
      @conn = UNIXSocket.new(@socket)
      # warn "#{op}/wait"
      d = <<-CONT_WAIT
GET #{op}/wait HTTP/1.1
Host: a
User-Agent: site-manager/1.0
Accept: */*

CONT_WAIT

      @conn.write d
      answer = get_answer
      warn "** #{answer}" if @debug
      return answer
    end
  end
end