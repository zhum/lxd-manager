require 'socket'
#
# Class SockMock provides mock for lxd socket
#
# @author serg
#
class SockMock
  IMAGES = <<_IMAGES.freeze
"type": "sync",
"status": "Success",
"status_code": 200,
"operation": "",
"error_code": 0,
"error": "",
"metadata": [
"/1.0/images/1234567890qwertyuiopasdfghjklzxcvbnmqweqweqweqweqweqweqweqweqweq",
"/1.0/images/qqqqqqqqqqqqqqqwwwwwwwwwwwwwwwwwweeeeeeeeeeeeeerrrrrrrrrrrr11111"
]
_IMAGES
  CONTS = <<_CONTS.freeze
"type": "sync",
"status": "Success",
"status_code": 200,
"operation": "",
"error_code": 0,
"error": "",
"metadata": [
"/1.0/containers/test1",
"/1.0/containers/cont2",
"/1.0/containers/test2"
]
_CONTS
  PROFILES = <<_PROFS.freeze
"type": "sync",
"status": "Success",
"status_code": 200,
"operation": "",
"error_code": 0,
"error": "",
"metadata": [
"/1.0/profiles/prof1",
"/1.0/profiles/prof2",
"/1.0/profiles/prof3"
]
_PROFS

  CONT = <<_CONT
"type": "sync",
"status": "Success",
"status_code": 200,
"operation": "",
"error_code": 0,
"error": "",
"metadata": {
  "architecture": "x86_64",
  "config": {
    "image.architecture": "amd64"
  },
  "profiles": [
    "prof1","prof2"
  ],
  "stateful": false,
  "description": "my container",
  "expanded_config": {
    "image.architecture": "amd64"
  },
  "expanded_devices": {
    "eth0": {
      "name": "eth0",
      "nictype": "bridged",
      "parent": "intranet",
      "type": "nic"
    },
    "root": {
      "path": "/",
      "pool": "pool-dir",
      "type": "disk"
    }
  },
  "name": "test2",
  "status": "Running",
  "status_code": 103
}
_CONT

  CONT_CREATE = <<_CCREATE
"type": "sync",
"status": "Success",
"status_code": 200,
"operation": "",
"error_code": 0,
"error": "",
"metadata": {
  "id": "46320db5-4c2c-4ea4-8f26-b3998bb74280",
  "class": "task",
  "description": "Creating container",
  "status": "Running",
  "status_code": 103,
  "resources": {
    "containers": [
      "/1.0/containers/test3"
    ]
  },
  "metadata": null,
  "may_cancel": false,
  "err": ""
}

_CCREATE
  #
  # Constructor
  #
  # @param [String] path socket path
  # @param [Hash]   opts options...
  #
  def initialize(path, opts = {})
    begin File.delete(path) rescue Errno::ENOENT end
    @sock = UNIXServer.new(path)
    # warn "#{path} created (#{@sock})"
    @thread = Thread.new do
      conn = @sock.accept
      data = ''
      conn.each_line do |l|
        break if l.chomp == ''
        next unless l =~ /(GET|POST) (\S+)/
        path = Regexp.last_match(2)
        case path
        when '/1.0/images'
          data = IMAGES
          break
        when '/1.0/profiles'
          data = PROFILES
          break
        when '/1.0/containers'
          data = if Regexp.last_match(1) == 'GET'
            CONTS
          else
            CONT_CREATE
          end
          break
        when '/1.0/containers/test2'
          data = CONT
          break
        end
      end
      conn.puts <<DATA
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: #{2 + data.size}

{#{data}}
DATA
      conn.close
    end
  end

  def stop
    @thread.kill
  end
end
