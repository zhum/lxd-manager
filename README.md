# Lxd::Manager

This is a gem to interact with LXD container manager.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lxd-manager'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install lxd-manager

## Usage

Console usage (just for example): `lxd-manager`. This example can create, delete, start, stop and list containers.
After sucessfull container creation it starts automatically, then nginx-proxy is created (nginx-modsite script is required),
and xinetd ssh port-forward.

You can use the gem to create your own tools.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/zhum/lxd-manager. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/zhum/lxd-manager/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

