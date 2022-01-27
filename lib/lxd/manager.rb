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

    PROFILES_ATTRS = {
      # name => type, defaults, live update, condition, description
      'boot.autostart' => ['boolean', '-', 'n/a', '-', 'Always start the instance when LXD starts (if not set, restore last state)'],
      'boot.autostart.delay' => ['integer', '0', 'n/a', '-', 'Number of seconds to wait after the instance started before starting the next one'],
      'boot.autostart.priority' => ['integer', '0', 'n/a', '-', 'What order to start the instances in (starting with highest)'],
      'boot.host_shutdown_timeout' => ['integer', '30', 'yes', '-', 'Seconds to wait for instance to shutdown before it is force stopped'],
      'boot.stop.priority' => ['integer', '0', 'n/a', '-', 'What order to shutdown the instances (starting with highest)'],
      'cloud-init.network-config' => ['string', 'DHCP on eth0', 'no', '-', 'Cloud-init network-config, content is used as seed value'],
      'cloud-init.user-data' => ['string', '#cloud-config', 'no', '-', 'Cloud-init user-data, content is used as seed value'],
      'cloud-init.vendor-data' => ['string', '#cloud-config', 'no', '-', 'Cloud-init vendor-data, content is used as seed value'],
      'cluster.evacuate' => ['string', 'auto', 'n/a', '-', 'What to do when evacuating the instance (auto, migrate, live-migrate, or stop)'],
      'environment.*' => ['string', '-', 'yes (exec)', '-', 'key/value environment variables to export to the instance and set on exec'],
      'limits.cpu' => ['string', '-', 'yes', '-', 'Number or range of CPUs to expose to the instance (defaults to 1 CPU for VMs)'],
      'limits.cpu.allowance' => ['string', '100%', 'yes', 'container', 'How much of the CPU can be used. Can be a percentage (e.g. 50%) for a soft limit or hard a chunk of time (25ms/100ms)'],
      'limits.cpu.priority' => ['integer', '10 (maximum)', 'yes', 'container', 'CPU scheduling priority compared to other instances sharing the same CPUs (overcommit) (integer between 0 and 10)'],
      'limits.disk.priority' => ['integer', '5 (medium)', 'yes', '-', 'When under load, how much priority to give to the instance’s I/O requests (integer between 0 and 10)'],
      'limits.hugepages.64KB' => ['string', '-', 'yes', 'container', 'Fixed value in bytes (various suffixes supported, see below) to limit number of 64 KB hugepages (Available hugepage sizes are architecture dependent.)'],
      'limits.hugepages.1MB' => ['string', '-', 'yes', 'container', 'Fixed value in bytes (various suffixes supported, see below) to limit number of 1 MB hugepages (Available hugepage sizes are architecture dependent.)'],
      'limits.hugepages.2MB' => ['string', '-', 'yes', 'container', 'Fixed value in bytes (various suffixes supported, see below) to limit number of 2 MB hugepages (Available hugepage sizes are architecture dependent.)'],
      'limits.hugepages.1GB' => ['string', '-', 'yes', 'container', 'Fixed value in bytes (various suffixes supported, see below) to limit number of 1 GB hugepages (Available hugepage sizes are architecture dependent.)'],
      'limits.kernel.*' => ['string', '-', 'no', 'container', 'This limits kernel resources per instance (e.g. number of open files)'],
      'limits.memory' => ['string', '-', 'yes', '-', 'Percentage of the host’s memory or fixed value in bytes (various suffixes supported, see below) (defaults to 1GiB for VMs)'],
      'limits.memory.enforce' => ['string', 'hard', 'yes', 'container', 'If hard, instance can’t exceed its memory limit. If soft, the instance can exceed its memory limit when extra host memory is available'],
      'limits.memory.hugepages' => ['boolean', 'false', 'no', 'virtual-machine', 'Controls whether to back the instance using hugepages rather than regular system memory'],
      'limits.memory.swap' => ['boolean', 'true', 'yes', 'container', 'Controls whether to encourage/discourage swapping less used pages for this instance'],
      'limits.memory.swap.priority' => ['integer', '10 (maximum)', 'yes', 'container', 'The higher this is set, the least likely the instance is to be swapped to disk (integer between 0 and 10)'],
      'limits.network.priority' => ['integer', '0 (minimum)', 'yes', '-', 'When under load, how much priority to give to the instance’s network requests (integer between 0 and 10)'],
      'limits.processes' => ['integer', '- (max)', 'yes', 'container', 'Maximum number of processes that can run in the instance'],
      'linux.kernel_modules' => ['string', '-', 'yes', 'container', 'Comma separated list of kernel modules to load before starting the instance'],
      'linux.sysctl.*' => ['string', '-', 'no', 'container', 'Allow for modify sysctl settings'],
      'migration.incremental.memory' => ['boolean', 'false', 'yes', 'container', 'Incremental memory transfer of the instance’s memory to reduce downtime'],
      'migration.incremental.memory.goal' => ['integer', '70', 'yes', 'container', 'Percentage of memory to have in sync before stopping the instance'],
      'migration.incremental.memory.iterations' => ['integer', '10', 'yes', 'container', 'Maximum number of transfer operations to go through before stopping the instance'],
      'migration.stateful' => ['boolean', 'false', 'no', 'virtual-machine', 'Allow for stateful stop/start and snapshots. This will prevent the use of some features that are incompatible with it'],
      'nvidia.driver.capabilities' => ['string', 'compute,utility', 'no', 'container', 'What driver capabilities the instance needs (sets libnvidia-container NVIDIA_DRIVER_CAPABILITIES)'],
      'nvidia.runtime' => ['boolean', 'false', 'no', 'container', 'Pass the host NVIDIA and CUDA runtime libraries into the instance'],
      'nvidia.require.cuda' => ['string', '-', 'no', 'container', 'Version expression for the required CUDA version (sets libnvidia-container NVIDIA_REQUIRE_CUDA)'],
      'nvidia.require.driver' => ['string', '-', 'no', 'container', 'Version expression for the required driver version (sets libnvidia-container NVIDIA_REQUIRE_DRIVER)'],
      'raw.apparmor' => ['blob', '-', 'yes', '-', 'Apparmor profile entries to be appended to the generated profile'],
      'raw.idmap' => ['blob', '-', 'no', 'unprivileged container', 'Raw idmap configuration (e.g. “both 1000 1000”)'],
      'raw.lxc' => ['blob', '-', 'no', 'container', 'Raw LXC configuration to be appended to the generated one'],
      'raw.qemu' => ['blob', '-', 'no', 'virtual-machine', 'Raw Qemu configuration to be appended to the generated command line'],
      'raw.seccomp' => ['blob', '-', 'no', 'container', 'Raw Seccomp configuration'],
      'security.devlxd' => ['boolean', 'true', 'no', '-', 'Controls the presence of /dev/lxd in the instance'],
      'security.devlxd.images' => ['boolean', 'false', 'no', 'container', 'Controls the availability of the /1.0/images API over devlxd'],
      'security.idmap.base' => ['integer', '-', 'no', 'unprivileged container', 'The base host ID to use for the allocation (overrides auto-detection)'],
      'security.idmap.isolated' => ['boolean', 'false', 'no', 'unprivileged container', 'Use an idmap for this instance that is unique among instances with isolated set'],
      'security.idmap.size' => ['integer', '-', 'no', 'unprivileged container', 'The size of the idmap to use'],
      'security.nesting' => ['boolean', 'false', 'yes', 'container', 'Support running lxd (nested) inside the instance'],
      'security.privileged' => ['boolean', 'false', 'no', 'container', 'Runs the instance in privileged mode'],
      'security.protection.delete' => ['boolean', 'false', 'yes', '-', 'Prevents the instance from being deleted'],
      'security.protection.shift' => ['boolean', 'false', 'yes', 'container', 'Prevents the instance’s filesystem from being uid/gid shifted on startup'],
      'security.agent.metrics' => ['boolean', 'true', 'no', 'virtual-machine', 'Controls whether the lxd-agent is queried for state information and metrics'],
      'security.secureboot' => ['boolean', 'true', 'no', 'virtual-machine', 'Controls whether UEFI secure boot is enabled with the default Microsoft keys'],
      'security.syscalls.allow' => ['string', '-', 'no', 'container', 'A ‘\n’ separated list of syscalls to allow (mutually exclusive with security.syscalls.deny*)'],
      'security.syscalls.deny' => ['string', '-', 'no', 'container', 'A ‘\n’ separated list of syscalls to deny'],
      'security.syscalls.deny_compat' => ['boolean', 'false', 'no', 'container', 'On x86_64 this enables blocking of compat_* syscalls, it is a no-op on other arches'],
      'security.syscalls.deny_default' => ['boolean', 'true', 'no', 'container', 'Enables the default syscall deny'],
      'security.syscalls.intercept.bpf' => ['boolean', 'false', 'no', 'container', "Handles the 'bpf' system call" ],
      'security.syscalls.intercept.bpf.devices' => ['boolean', 'false', 'no', 'container', 'Allows "bpf" programs for the devices cgroup in the unified hierarchy to be loaded.'],
      'security.syscalls.intercept.mknod' => ['boolean', 'false', 'no', 'container', 'Handles the "mknod" and "mknodat" system calls (allows creation of a limited subset of char/block devices'],
      'security.syscalls.intercept.mount' => ['boolean', 'false', 'no', 'container', 'Handles the "mount" system call'],
      'security.syscalls.intercept.mount.allowed' => ['string', '-', 'yes', 'container', 'Specify a comma-separated list of filesystems that are safe to mount for processes inside the instance'],
      'security.syscalls.intercept.mount.fuse' => ['string', '-', 'yes', 'container', 'Whether to redirect mounts of a given filesystem to their fuse implemenation (e.g. ext4=fuse2fs)'],
      'security.syscalls.intercept.mount.shift' => ['boolean', 'false', 'yes', 'container', 'Whether to mount shiftfs on top of filesystems handled through mount syscall interception'],
      'security.syscalls.intercept.setxattr' => ['boolean', 'false', 'no', 'container', 'Handles the "setxattr" system call (allows setting a limited subset of restricted extended ,attributes)'],
      'snapshots.schedule' => ['string', '-', 'no', '-', 'Cron expression (<minute> <hour> <dom> <month> <dow>), or a comma separated list of schedule aliases <@hourly> <@daily> <@midnight> <@weekly> <@monthly> <@annually> <@yearly> <@startup>)'], 
      'snapshots.schedule.stopped' => ['bool', 'false', 'no', '-', 'Controls whether or not stopped instances are to be snapshoted automatically'],
      'snapshots.pattern' => ['string', 'snap%d', 'no', '-', 'Pongo2 template string which represents the snapshot name (used for scheduled snapshots and unnamed snapshots)'],
      'snapshots.expiry' => ['string', '-', 'no', '-', 'Controls when snapshots are to be deleted (expects expression like "1M", "2H", "3d", "4w", "5m", "6y")'],
      'user.*' => ['string', '-', 'n/a', '-', 'Free form user key/value storage (can be used in search)']
    }.freeze

    ##
    ## Get all possible profile attrs descriptions
    ##
    ## @return   hash like {name => [type, defaults, live update, condition, description]}
    ##
    def self.profiles_attrs
      PROFILES_ATTRS
    end

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
      lxd.get("/1.0/#{@inst}/#{name}/state")
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

    ##
    ## Gets the container ip.
    ##
    ## @param      name  The container name
    ##
    def get_container_ip(name)
      st = nil
      net = nil
      count = @max_wait_count
      loop do
        st = @lxd.container_state(name)
        net = st && st['metadata'] && st['metadata']['network']
        break if net &&
                 net['eth0'] &&
                 !net['eth0']['addresses'].empty? &&
                 net['eth0']['addresses'].any? { |x| x['family'] == 'inet' }
        sleep 0.2
        count -= 1
        return nil if count < 0
      end
      addr = net['eth0']['addresses'].select { |x| x['family'] == 'inet' }
      addr.empty? ? nil : addr[0]['address']
    end
  end
end
