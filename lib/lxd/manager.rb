#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

module LXD
  #
  # Class LXD::Manager provides creation/updateing/deleting sites
  # Example
  #
  # @author Sergey Zhumatiy <serg@parallel.ru>
  #
  class Manager
    #
    # @!attribute [r] acme
    #   @return [String] acme.sh directory [/root/.acme.sh]
    attr_reader :acme
    #
    # @!attribute [r] xinetd
    #   @return [String] path to xinetd.d [/etc/xinetd.d]
    attr_reader :xinetd
    #
    # @!attribute [r] xinetd_tpl
    #   @return [String] path to xinetd service template
    attr_reader :xinetd_tpl
    #
    # @!attribute [r] nginx
    #   @return [String] path to ngix config dir [/etc/nginx]
    attr_reader :nginx
    #
    # @!attribute [r] nginx_tpl
    #   @return [String] path to ngix site template [/etc/nginx/site-template]
    attr_reader :nginx_tpl
    #
    # @!attribute [rw] last_port
    #   @return [Integer] last used port for ssh forwarfing
    attr_accessor :last_port
    #
    # @!attribute [r] lxd_socket
    #   @return [String] path to lxd socket
    #                    [/var/snap/lxd/common/lxd/unix.socket]
    attr_reader :lxd_socket

    DEFS = {
      acme: '/root/.acme.sh',
      xinetd: '/etc/xinetd.d',
      xinetd_tpl: '/etc/xinetd_ssh_template',
      nginx: '/etc/nginx',
      nginx_tpl: '/etc/nginx/site-template',
      last_port: 22_222,
      lxd_socket: '/var/snap/lxd/common/lxd/unix.socket',
      debug: nil
    }.freeze

    #
    # Constructor
    #
    # @param [Hash] args <description>
    #
    def initialize(args = {})
      DEFS.each do |key, value|
        value = args[key] if args[key]
        instance_variable_set("@#{key}", value)
      end
    end

    def lxd
      @lxd ||= LXD::Socket.new(socket: @lxd_socket, debug: @debug)
    end

    #
    # Created new site configs
    #
    # @param [String] host   Site name
    # @param [String] cont   Container object (definition)
    #
    # @return [Bool] true if site configs created
    #
    def create_configs(host, cont)
      ok = create_nginx_conf(host, cont)

      ok = create_xinetd_conf(host, cont) if ok
      ok = create_lxd_vm(host, cont) if ok
      ok
    end

    #
    #
    # Renrew ssl certificate for site
    #
    # @return [bool] true if certificate was actually updated
    #
    def update_ssl(host)
      system("#{@acme}/acme.sh --renew -d #{host} >> #{LOG}") \
      && \
      system("#{@acme}/acme.sh --install-cert -d #{host} --cert-file /etc/ssl/certs/#{host}.crt --key-file /etc/ssl/certs/#{host}.key --fullchain-file /etc/ssl/certs/#{host}.full >> #{LOG}")
    end

    #
    # Issue new certificate for site
    #
    #
    # @return [boot] true if certificate was issued
    #
    def issue_ssl(host)
      system "#{@acme}/acme.sh --issue -d #{host} >> #{LOG}"
    end

    #
    # Creates a new container via LXC API
    #
    # @param [String] cont Container description
    #
    # @return [Json] LXD answer
    #
    def create_lxd_vm(cont)
      json = {
        name: cont.name,
        source: {
          type: 'image',
          protocol: 'simplestreams',
          fingerprint: cont.image_fingerprint
        },
        profiles: cont.profiles
      }
      # json = URI.encode_www_form(json.to_json)
      json = json.to_json

      # warn ">> #{json}"
      answer = lxd.post(json, '/1.0/containers')
      answer
      # warn answer
    end

    #
    #  Create NGINX site config
    #
    #  @return [bool]  true if created, false  if failed or already exists
    #
    def create_nginx_conf(host, cont)
      conf = "#{@nginx}/sites-available/#{host}.conf"
      return false if File.file? conf

      template = File.read(@nginx_tpl)
      template.gsub! '{host}', host
      template.gsub! '{local_ip}', cont.local_ip
      File.open(conf, 'w') { |f| f.print template }
      true
    end

    #
    #  Create xinetd ssh forward config
    #
    #  @return [bool]  true if created, false  if failed or already exists
    #
    def create_xinetd_conf(host, cont)
      conf = "#{@xinetd}/#{host}.conf"
      return false if File.file? conf

      template = File.read(@xinetd_tpl)
      template.gsub! '{host}', host
      template.gsub! '{cont}', cont
      template.gsub! '{port}', @last_port
      @last_port += 1
      File.open(conf, 'w') do |f|
        f.print template
      end
      true
    end

    #####################################################################
    #####################################################################
    #
    # Get all profiles
    #
    #
    # @return [Array] list of profile names
    #
    def profiles
      lxd.get('/1.0/profiles')['metadata']
    end

    #
    # Get one profile details
    #
    #
    # @return [Json|nil] profile details
    #
    def profile(name)
      lxd.get("/1.0/profiles/#{name}")['metadata']
    end

    #####################################################################
    #####################################################################
    #
    # Get all images
    #
    #
    # @return [Json] just LXD answer
    #
    def images
      lxd.get('/1.0/images')['metadata']
    end

    #
    # Get image by fingerprint
    #
    # @param [String] fingerprint
    #
    # @return [Json] just LXD answer
    #
    def image(fingerprint)
      lxd.get("/1.0/images/#{fingerprint}")['metadata']
    end

    #
    # Get image by fingerprint
    #
    #
    # @return [Json] just LXD answer
    #
    def image_by_fingerprint(fingerprint)
      lxd.get("/1.0/images/#{fingerprint}")
    end

    #
    # get fingerprint of named image
    #
    # @param [String] name name of image
    #
    # @return [String|nil] fingerprint if found
    #
    def fingerprint_by_imagename(name)
      images.each do |f|
        fp = f.split('/').last
        im = image(fp)
        # warn im
        next unless im && im['aliases']
        im['aliases'].each { |e| return fp if e['name'] == name }
        return fp if im['update_source'] &&
                     im['update_source']['alias'] == name
      end
      nil
    end
    #####################################################################
    #####################################################################
    #
    # Get all containers
    #
    #
    # @return [Json] just LXD answer
    #
    def containers
      lxd.get('/1.0/containers')['metadata']
    end

    #
    # Get container by name
    #
    #
    # @return [LXD::Container] container descriprion
    #
    def container(name)
      c = lxd.get("/1.0/containers/#{name}")
      if c.empty?
        nil
      else
        LXD::Container.new(c)
      end
    end

    #
    # Create new container
    #
    # @param  [LXD::Container] cont  container description
    #
    # @return [Bool] true if container was created
    #
    def new_container(cont)
      # data = {
      #   name: name,                            # 64 chars max, ASCII, no slash, no colon and no comma
      #   # architecture: 'x86_64',
      #   profiles: ['default'],                 # List of profiles
      #   ephemeral: true,                       # Whether to destroy the container on shutdown
      #   config: { :'limits.cpu' => '2' },      # Config override.
      #   devices: {                             # optional list of devices the container should have
      #   },
      #   source: {
      #     type: 'image',                       # Can be: 'image', 'migration', 'copy' or 'none'
      #     fingerprint: 'SHA-256'               # Fingerprint
      #   }
      # }
      c = lxd.post("/1.0/containers", cont.to_json)
      if c.empty?
        false
      else
        c['metadata']['status_code'].to_i < 400
      end
    end

    # Get container state
    #
    # @param [String] name container name
    #
    # @return [Hash] state
    #
    def container_state(name)
      c = lxd.get("/1.0/containers/#{name}/state")
      c['metadata']
    end

    def update_state(name, data = nil)
      return false unless data
      c = lxd.put("/1.0/containers/#{name}/state", data)
    end
  end
end
