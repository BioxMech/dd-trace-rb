# Auto Instrumentation

`ddtrace` can automatically instrument all available libraries, without requiring the manual specification of each one.

## Rails

Add 'ddtrace', require: 'ddtrace/auto_instrument' to your Gemfile:

```ruby
source 'https://rubygems.org'
gem 'ddtrace', require: 'ddtrace/auto_instrument'
```

## Ruby

Require `'ddtrace/auto_instrument'` after all gems that you'd like to instrument have been loaded:

```ruby
# Example libraries with supported integrations
require 'sinatra'
require 'faraday'
require 'redis'

require 'ddtrace/auto_instrument'
```

## Additional configuration

You can reconfigure, override, or disable any specific integration settings by adding
a `Datadog.configure` call after `ddtrace/auto_instrument` is activated.
