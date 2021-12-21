#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'yaml'

module LXD
  #
  # Class LXD::Manager provides creation/updateing/deleting sites
  #
  # @author Sergey Zhumatiy <serg@parallel.ru>
  #
  class Manager
    #
    #   @return [Hash|nil] last error descripton
    attr_reader :err
    #
    #   @return [String] acme.sh directory [/root/.acme.sh]
    attr_reader :acme
    #
    #   @return [String] path to xinetd.d [/etc/xinetd.d]
    attr_reader :xinetd
    #
    #   @return [String] path to xinetd service template
    #                    [/etc/xinetd_ssh_template]
    attr_reader :xinetd_tpl
    #
    #   @return [String] path to nginx config dir [/etc/nginx]
    attr_reader :nginx
    #
    #   @return [String] path to ngix site template [/etc/nginx/site-template]
    attr_reader :nginx_tpl
    #
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
      debug: nil,
      config_path: '.lxd-manager.conf'
    }.freeze

    #
    # Constructor
    #
    # @param args [Hash] available options: `:acme`, `:xinetd`, `:xinetd_tpl`,
    #                                       `:nginx`,`:nginx_tpl`,`:lxd_socket`.
    #                                        See attributes descriptions.

    #
    def initialize(args = {})
      DEFS.merge(args).each do |key, value|
        value = args[key] if args[key]
        instance_variable_set("@#{key}", value)
      end
      if File.exist? @config_path
        opts = YAML.safe_load(File.read(@config_path))
        if opts
          opts.each do |key, value|
            value = args[key] if args[key]
            instance_variable_set("@#{key}", value)
          end
        end
      end
      @inst = args[:new_api] ? 'instances' : 'containers'
    end

    ##
    ## Saves current configuration into localfile
    ##
    def save_conf
      opts = Hash[ DEFS.keys.map do |k|
                     [k.to_s, instance_variable_get("@#{k}")]
                   end
      ]
      File.open(@config_path, 'w') { |f| f.print YAML.dump opts }
    end

    # Return current lxd connector
    #
    #
    # @return [LXD::Socket] lxd connector
    #
    def lxd
      @lxd ||= LXD::Socket.new(socket: @lxd_socket, debug: @debug)
    end

    #
    # Create new site configs
    #
    # @param host [String]   Site name
    # @param cont [String]   Container object (definition)
    #
    # @return [Bool, String] true and 'ok' if site configs created
    #                        false and fail reason on fail
    #
    def create_configs(host, cont, domain = nil)
      unless create_nginx_conf(host, cont, domain)
        return [false, 'Cannot create nginx config']
      end

      unless create_xinetd_conf(host, cont, domain)
        return [false, 'Cannot create xinetd config']
      end
      # return [false, 'Cannot create vm'] unless create_lxd_vm(cont)

      [true, 'ok']
    end

    #
    # Delete site configs
    #
    # @param host [String]   Site name
    # @return [Bool, String] true and 'ok' if site configs created
    #                        false and fail reason on fail
    #
    def delete_configs(host)
      unless delete_nginx_conf(host)
        return [false, 'Cannot delete nginx config']
      end

      unless delete_xinetd_conf(host)
        return [false, 'Cannot delete xinetd config']
      end
      # return [false, 'Cannot create vm'] unless create_lxd_vm(cont)

      [true, 'ok']
    end

    #
    # Renrew the ssl certificate for site
    #
    # @return [bool] true if certificate was actually updated
    #
    def update_ssl(host)
      system("#{@acme}/acme.sh --renew -d #{host} >> #{LOG}") \
      && \
      system("#{@acme}/acme.sh --install-cert -d #{host} --cert-file /etc/ssl/certs/#{host}.crt --key-file /etc/ssl/certs/#{host}.key --fullchain-file /etc/ssl/certs/#{host}.full >> #{LOG}")
    end

    #
    # Issues a new certificate for site
    #
    # @return [boot] true if certificate was issued
    #
    def issue_ssl(host)
      system "#{@acme}/acme.sh --issue -d #{host} >> #{LOG}"
    end

    #
    # Creates a new container via LXC API
    #
    # @param cont [String] Container description
    #
    # @return [Json] LXD answer
    #
    def create_lxd_vm(cont)
      json = {
        name: cont.name,
        source: {
          type: 'image',
          protocol: 'simplestreams',
          fingerprint: cont.fingerprint
        },
        profiles: cont.profiles
      }
      # json = URI.encode_www_form(json.to_json)
      json = json.to_json

      warn ">> #{json}"
      answer = lxd.post("/1.0/#{@inst}", json)
      warn "create_lxd_vm: #{answer.inspect}"
      answer['status'] == 'Success'
    end

    #
    #  Create NGINX site config
    #
    #  @param   host [String]   hostname
    #  @param   cont [LXD::Container] container description
    #  @param   fullhost [String, nil] full hostname
    #  @return  [bool]  true if created, false  if failed or already exists
    #
    def create_nginx_conf(host, cont, fullhost = nil)
      conf = "#{@nginx}/sites-available/#{host}.conf"
      return false if File.file? conf

      template = File.read(@nginx_tpl)
      template.gsub! '{host}', host
      template.gsub! '{fullhost}', (fullhost || host)
      template.gsub! '{local_ip}', cont.local_ip
      File.open(conf, 'w') { |f| f.print template }
      true
    end

    #
    #  Delete NGINX site config
    #
    #  @param  host  [String]  hostname
    #  @return [bool]  true if created, false  if failed or already exists
    #
    def delete_nginx_conf(host)
      conf = "#{@nginx}/sites-available/#{host}.conf"
      return false unless File.file? conf
      File.delete(conf)
    end

    # Check if xinetd last port is available and find first free if not
    #
    def correct_last_port
      used = `ss -lpnt -f inet | awk '{print $4}'`
             .split("\n")
             .map { |l| l.split(':')[1].to_i }
      @last_port += 1 while used.include? @last_port
    end

    #  Create xinetd ssh forward config
    #
    #  @param   host [String]   hostname
    #  @param   cont [LXD::Container] container description
    #  @param   fullhost [String, nil] full hostname
    #  @return  [bool]  true if created, false  if failed or already exists
    #
    def create_xinetd_conf(host, cont, fullhost = nil)
      conf = "#{@xinetd}/ssh_#{host}"
      # warn "xinetd cont = #{conf}"
      return false if File.file? conf

      # warn "lp = #{@last_port}"
      correct_last_port
      template = File.read(@xinetd_tpl)
      template.gsub! '{host}', host
      template.gsub! '{fullhost}', (fullhost || host)
      template.gsub! '{local_ip}', cont.local_ip
      template.gsub! '{port}', @last_port.to_s
      @last_port += 1
      save_conf
      File.open(conf, 'w') do |f|
        f.print template
      end
      true
    end

    #  Delete xinetd ssh forward config
    #
    #  @param   host [String]   hostname
    #  @return  [bool]  true if created, false  if failed or already exists
    #
    def delete_xinetd_conf(host)
      conf = "#{@xinetd}/ssh_#{host}"
      return false unless File.file? conf
      File.delete(conf)
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
    # @param  fingerprint[String]  The fingerprint
    #
    # @return [Json] just LXD answer
    #
    def image_by_fingerprint(fingerprint)
      lxd.get("/1.0/images/#{fingerprint}")['metadata']
    end

    #
    # Get fingerprint of named image
    #
    # @param name [String] name of image
    #
    # @return [String|nil] fingerprint if found
    #
    def fingerprint_by_imagename(name)
      images.each do |f|
        fp = f.split('/').last
        im = image(fp)
        warn "f_by_i #{im.inspect}" if @debug
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
      lxd.get("/1.0/#{@inst}")['metadata']
    end

    #
    # Get container by name
    #
    #
    # @param      name [String]  The container name
    # @return     [LXD::Container] The container descriprion
    #
    def container(name)
      c = lxd.get("/1.0/#{@inst}/#{name}")
      if c.empty?
        nil
      else
        LXD::Container.new(c)
      end
    end

    ##
    ## Creates a new LXD::Container by json answer
    ##
    ## @param      [Hash] c json data
    ##
    def container_by_json(c)
      warn c['metadata'].inspect
      if c.nil? || c.empty? || c['original_status'].to_i >= 400
        @err = c
        nil
      elsif c['metadata'] &&
            c['metadata']['status_code'] &&
            c['metadata']['status_code'].to_i < 400
        LXD::Container.new(c)
      else
        @err = c
        nil
      end
    end

    #
    # Create new container
    #
    # @param  cont [Hash|JSON]  container description
    #
    # @return [LXD::Container|nil] new container or nil
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
      # warn "--> #{cont.to_json}"
      c = lxd.post("/1.0/#{@inst}", cont.to_json)
      # warn "c = #{c}"
      container_by_json(c)
    end

    # Delete container
    #
    # @param name [String]  container name
    #
    def delete(name)
      lxd.delete("/1.0/#{@inst}/#{name}")
    end

    # Get container state
    #
    # @param name [String] container name
    #
    # @return [Hash] state
    #
    def container_state(name)
      c = lxd.get("/1.0/#{@inst}/#{name}/state")
      # c['metadata']
      #container_by_json(c)
    end

    # Change state of a container by name
    #
    # @param name [String] container name
    # @param data [Hash] new state description
    #
    # Example:
    #   m.update_state 'my_container', action: 'start'
    #
    # @return [Hash|false] New state description or nil
    #
    def update_state(name, data = nil)
      return nil unless data
      update = {
        force: true,
        stateful: false,
        timeout: 30
      }.merge(data).transform_keys(&:to_s)

      warn "--> #{update.to_json.inspect} /1.0/#{@inst}/#{name}/state"
      lxd.put("/1.0/#{@inst}/#{name}/state", update.to_json)
    end
  end
end
