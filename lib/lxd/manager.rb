#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

module LXD
  #
  # Class LXD::Manager provides creation/updateing/deleting sites
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
    #   @return [String] path to ngix site template [/wtc/nginx/site-template]
    attr_reader :nginx_tpl
    #
    # @!attribute [rw] last_port
    #   @return [Integer] last used port for ssh forwarfing
    attr_accessor :last_port
    #
    # @!attribute [r] lxd_socket
    #   @return [String] path to lxd socket [/var/snap/lxd/common/lxd/unix.socket]
    attr_reader :lxd_socket

    def initialize(args={})
      @acme       = args[:acme] || '/root/.acme.sh'
      @xinetd     = args[:xinetd] || '/etc/xinetd.d'
      @xinetd_tpl = args[:xinetd_tpl] || '/etc/xinetd_ssh_template'
      @nginx      = args[:nginx] || '/etc/nginx'
      @nginx_tpl  = args[:nginx_tpl] || '/etc/nginx/site-template'
      @last_port  = (args[:last_port] || 22222).to_i
      @lxd_socket = args[:lxd_socket] || '/var/snap/lxd/common/lxd/unix.socket'
      @debug      = args[:debug]
    end
    
    def lxd
      @lxd ||= LXD::Socket.new(socket: @lxd_socket, debug: @debug)
    end

    #
    # Created new site configs
    #
    # @param [String] site   Site name
    #
    # @return [Bool] true if site configs created
    #
    def create_configs(host, cont)
      ok = create_nginx_conf(host, cont)
      if ok
        ok = create_xinetd_conf(host, cont)
      end
      if ok
        ok = create_lxd_vm(host, cont)
      end
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

    def create_lxd_vm(host, cont)
      json = {
        name: cont.name,
        source: {
          type: "image",
          protocol: "simplestreams",
          fingerprint: "#{cont.image_fingerprint}"
        },
        profiles: cont.profiles
      }
      #json = URI.encode_www_form(json.to_json)
      json = json.to_json

      # warn ">> #{json}"
      answer = lxd.post(json, '/1.0/containers')

      # warn answer
    end

    #
    #  Create NGINX site config
    #  
    #  
    #  @return [bool]  true if created, false  if failed or already exists
    #
    def create_nginx_conf(host, cont)
      conf = "#{@nginx}/sites-available/#{host}.conf"
      return false if File.file? conf

      template = File.read(@nginx_tpl)
      template.gsub! '{host}', host
      template.gsub! '{local_ip}', cont.local_ip
      File.open(conf, 'w'){|f|
        f.print template
      }
      true
    end

    #
    #  Create xinetd ssh forward config
    #  
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
      File.open(conf, 'w'){|f|
        f.print template
      }
      true
    end


    def get_containers
      lxd.get('/1.0/containers')
    end

    def get_images
      lxd.get('/1.0/images')
    end

    def get_image fingerprint
      lxd.get("/1.0/images/#{fingerprint}")
    end
  end
end
