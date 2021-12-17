# frozen_string_literal: true

require 'socket'
require 'net/http'

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
    # socket::  path to socket [/var/snap/lxd/common/lxd/unix.socket]
    #
    def initialize(args = {})
      # warn "--- #{args}"
      @socket = args[:socket] || '/var/snap/lxd/common/lxd/unix.socket'
      @debug = args[:debug]
      @conn = nil
    end

    ##
    ## @brief      make a request to LXD server
    ##
    ## @param      path    The request path
    ## @param      method  The method - :get, :put, :post
    ## @param      [data]  The data to send
    ##
    def req(path, method, data = nil)
      sock = Net::BufferedIO.new(UNIXSocket.new(@socket))
      request =
        case method
        when :get
          Net::HTTP::Get.new(path)
        when :put
          Net::HTTP::Put.new(path)
        when :post
          Net::HTTP::Post.new(path)
        when :delete
          Net::HTTP::Delete.new(path)
        else
          raise "Bad method '#{method}'"
        end
      request['host'] = 'a'
      request.body = data if data
      warn "> #{method}: #{path} -> #{request.body}" if @debug
      request.exec(sock, '1.1', path)

      response = nil
      loop do
        response = Net::HTTPResponse.read_new(sock)
        break unless response.kind_of?(Net::HTTPContinue)
      end
      response.reading_body(sock, request.response_body_permitted?) {}

      warn "response = #{response.inspect}" if @debug
      answer = if response.kind_of?(Net::HTTPSuccess)
                 JSON.parse(response.body)
               else
                 { code: response.code, failed: true }
               end

      op = answer['operation'].to_s
      if op != ''
        # warn "WAIT..."
        answer = wait_operation op
      end
      warn "req answer: #{answer.inspect}" if @debug
      answer
    end

    #
    # Send data with GET method and get answer
    #
    # @param [String] path path
    #
    # @return [Bool] true if success
    #
    def get(path)
      # send_data(path, nil, 'GET')
      req(path, :get)
      # warn response.code
    end

    #
    # Send data with DELETE method and get answer
    #
    # @param [String] path path
    #
    # @return [Bool] true if success
    #
    def delete(path)
      req(path, :delete)
      # warn response.code
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
      # send_data(path, data, 'POST')
      req(path, :post, data)
    end

    #
    # Send data with PUT method and get answer
    #
    # @param [String] path path
    # @param [String] data data to send (json format)
    #
    # @return [Bool] true if success
    #
    def put(path, data)
      # send_data(path, data, 'PUT')
      req(path, :put, data)
    end

    #
    # Read and parse to json answer from socket
    #
    #
    # @return [Hash] answer from LXD server
    #                If fail, return {status: 999, original_status: status,
    #                length: result_len, headers: [response headers array]}
    #
    def get_answer
      status = nil
      length = nil
      headers = []
      loop do
        answer = @conn.readline.chomp
        headers << answer
        warn "<< #{answer}" if @debug
        case answer
        when %r{HTTP\/[0-9.]+ (\d+)}
          status = $1.to_i
        when %r{Content-Length: (\d+)}
          length = $1.to_i
        when %r{^$}
          break
        end
      end

      length = length.to_i
      @status = status.to_i
      if @status < 1 || @status > 399
        return {
          status: 999,
          original_status: @status,
          length: length,
          headers: headers
        }.to_json
      end
      data = @conn.read(length)
      warn "data=>'#{data}'"
      JSON.parse(data)
    end

    #
    # Send data to LXD and read answer
    #
    # @param [String] path path
    # @param [String] data JSON formatted data to send
    # @param [String] method GET/POST/PUT/...
    #
    # @return [String] answer in JSON format
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
        # warn "WAIT..."
        answer = wait_operation op
      end
      warn "!! #{answer}" if @debug
      @conn.close
      answer
    end

    # Send request for async operation wait and get answer
    #
    # @return [Hash] answer form LXD
    #
    def wait_operation(op)
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
      answer
    end
  end
end
