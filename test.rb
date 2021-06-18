#!/usr/bin/env ruby
# frozen_string_literal: true

require "#{File.dirname(__FILE__)}/lib/lxd-manager"
require 'optparse'
require 'yaml'

DEF_CONF = '/root/ssl-sites.yml'.freeze
LOG = "/tmp/manage-site-#{ENV['USER']}.log".freeze

# load config
# data = YAML.safe_load(ARGV[0] || DEF_CONF)

# reset log
File.open(LOG, 'w') { |f| }

# c = LXD::Container.new(
#   name: 'test12',
#   image_fingerprint: '1b6a6d7a59ebe17e1cc000c3501e1175964b936deae40b132d9ff4e3ea244269',
#   profiles: ['disk-data0', 'net-intranet']
# )

m = LXD::Manager.new
# answer = m.profiles
# pp(answer)

# pp m.new_container(
#   profiles: ['disk-local'],
#   name: 'test11',
#   source: { type: 'none' }
#   )

image = m.fingerprint_by_imagename('a1')
# pp image
# exit 0
c = m.new_container(
  profiles: ['disk-local'],
  name: 'test13',
  source: { type: 'image', protocol: 'simplestreams', fingerprint: image }
)
pp c
# pp m.container 'test12'
# pp m.container_state 'test12'
# print "----\n"
# stop, start, restart, freeze or unfreeze
# pp m.update_state 'test12', action: 'unfreeze'
# , timeout: 10
# print "----\n"

m.update_state 'test13', action: 'start'
st = nil
loop do
  st = m.container_state('test13')
  break unless
    st['network'].empty? ||
    (st['network']['lo']['addresses'] &&
     st['network']['lo']['addresses'].empty?
    )
  sleep 0.2
end
pp st
local_ip = st['network']['lo']['addresses'][0]['address']
c.local_ip = local_ip
pp m.create_configs('test13.parallel.ru', c)
