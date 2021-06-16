$VERBOSE = nil
require 'minitest/autorun'
require 'minitest/display'


MiniTest::Display.options = {
    suite_names: true,
    color: true,
    print: {
      success: "OK ",
      failure: "FAIL ",
      error: "ERR!! "
    }
  }

require "socket"
require 'lxd-manager'

class SockMock
	def initialize path, opts={}
		begin File.delete(path) rescue Errno::ENOENT end
		@sock = UNIXServer.new(path)
		#warn "#{path} created (#{@sock})"
    @thread = Thread.new do
			conn = @sock.accept
			data = ''
			conn.each_line{ |l|
				next unless l =~ /GET (\S+)/
				path = $1
				case path
				when '/1.0/images'
					data = <<IMAGES
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
IMAGES
				break
				when '/1.0/containers'
					data = <<CONT
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
CONT
				break
				end
			}
			conn.puts <<DATA
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: #{2+data.size}

{#{data}}
DATA
		conn.close
		end
	end

	def stop
		@thread.join
	end
end

SOCK = '/tmp/lxd-manager-test.sock'
describe LXD::Manager do
  before do
  	@m = LXD::Manager.new(lxd_socket: SOCK)
  	@mock = SockMock.new(SOCK)
  end

  after do
  	@mock.stop
  end

	describe "get list of images" do
		it "should return images list" do
			_(@m.get_images['metadata'].size).must_equal 2
		end
	end

	describe "get list of containers" do
		it "should return containers list" do
			_(@m.get_containers['metadata'].size).must_equal 3
		end
	end
end
