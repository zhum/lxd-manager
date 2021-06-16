$VERBOSE = nil
require 'minitest/autorun'

require './lib/lxd-manager'
require './tests/sock_mock.rb'

SOCK = '/tmp/lxd-manager-test.sock'.freeze
describe LXD::Manager do
  before do
    # warn 'start'
    @m = LXD::Manager.new(lxd_socket: SOCK)
    @mock = SockMock.new(SOCK)
    # warn 'end'
  end

  after do
    @mock.stop
  end

  describe 'get list of images' do
    it 'should return array of images' do
      _(@m.images).must_be_kind_of Array
    end

    it 'should return images list' do
      _(@m.images.size).must_equal 2
    end
  end
end
