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

  describe 'get list of profiles' do
    it 'should return array of profiles' do
      _(@m.profiles).must_be_kind_of Array
    end

    it 'should return profiles list' do
      _(@m.profiles.size).must_equal 3
    end
  end
end
