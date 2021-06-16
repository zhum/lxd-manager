# frozen_string_literal: true

module LXD
  #
  # Class LXD::Container provides a simple LXD container description
  #
  # @author Sergey Zhumatiy <serg@parallel.ru>
  #
  class Container
    #
    # @!attribute [rw] local_ip
    #   @return [String] local container ip
    attr_accessor :local_ip
    #
    # @!attribute [rw] name
    #   @return [String] container name
    attr_accessor :name
    #
    # @!attribute [r] image_fingerprint
    #   @return [String] image fingerprint
    attr_reader :image_fingerprint
    #
    # @!attribute [r] profiles
    #   @return [Array] list of LXD profile names
    attr_reader :profiles

    #
    # @!attribute [r] lxd
    #   @return [Hash] JSON from LXD
    attr_reader :lxd

    def initialize(args = {})
      m = args['metadata'] || {}
      @lxd      = args.clone
      @local_ip = args[:local_ip]
      @name     = args[:name] || m['name']
      @profiles = args[:profiles] || m['profiles']
      @image_fingerprint = args[:image_fingerprint]
    end
  end
end
