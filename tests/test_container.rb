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

  describe 'get list of containers' do
    it 'should return array of containers' do
      _(@m.containers).must_be_kind_of Array
    end

    it 'should return containers list' do
      _(@m.containers.size).must_equal 3
    end
  end

  describe 'work with containers' do
    it 'should get contaner by name' do
      @c = @m.container('test2')
      _(@c).must_be_kind_of LXD::Container

      _(@c.lxd['metadata']['name']).must_equal 'test2'
      _(@c.name).must_equal 'test2'
    end

    it 'should create a contaner' do
      # cont = {
      #   name: 'test3',
      #   # architecture: 'x86_64',
      #   profiles: ['default'],                 # List of profiles
      #   ephemeral: false,
      #   config: { :'limits.cpu' => '2' },      # Config override.
      #   # devices: {      # optional list of devices the container should have
      #   # },
      #   source: {
      #     type: 'image',    # Can be: 'image', 'migration', 'copy' or 'none'
      #     fingerprint: '123123123123123'  # Fingerprint
      #   }
      # }
      cont = {
        name: 'test3',
        source: {
          type: 'image',
          protocol: 'simplestreams',
          fingerprint: '123123123'
        },
        profiles: ['default']
      }
      @cont = @m.new_container(cont)
      _(@cont).must_equal true
    end
  end
end
