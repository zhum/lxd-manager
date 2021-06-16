#!/usr/bin/env ruby
# frozen_string_literal: true

require 'lxd-manager'
require 'optparse'
require 'yaml'

DEF_CONF = '/root/ssl-sites.yml'.freeze
LOG  = '/tmp/manage-site.log'.freeze

# load config
data = YAML.safe_load(ARGV[0] || DEF_CONF)

# reset log
File.open(LOG, 'w') { |f| }

c = LXD::Container.new(
  name: 'test12',
  image_fingerprint: '1b6a6d7a59ebe17e1cc000c3501e1175964b936deae40b132d9ff4e3ea244269',
  profiles: ['disk-data0', 'net-intranet']
)

m = LXD::Manager.new
answer = m.profiles
# pp(answer)

# pp m.new_container(
#   profiles: ['disk-local'],
#   name: 'test11',
#   source: { type: 'none' }
#   )

image = m.fingerprint_by_imagename('a1')
pp image
# exit 0
pp m.new_container(
  profiles: ['disk-local'],
  name: 'test12',
  source: { type: 'image', protocol: 'simplestreams', fingerprint: image }
)

pp m.container 'test12'