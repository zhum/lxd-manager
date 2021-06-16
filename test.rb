#!/usr/bin/env ruby
# frozen_string_literal: true

require 'lxd-manager'
require 'optparse'
require 'yaml'


DEF_CONF = '/root/ssl-sites.yml'
LOG  = '/tmp/manage-site.log'

# load config
data = YAML.load(ARGV[0] || DEF_CONF)

# reset log
File.open(LOG,'w'){|f|}


c = LXD::Container.new(
  name: 'test12',
  image_fingerprint: '1b6a6d7a59ebe17e1cc000c3501e1175964b936deae40b132d9ff4e3ea244269',
  profiles: ["disk-data0", "net-intranet"]
)

#answer = LXD::Manager.new().create_lxd_vm('testhost',c)
m = LXD::Manager.new()
answer = m.get_containers()
#answer = LXD::Manager.new().create_lxd_vm('testhost',c)

pp(answer)
