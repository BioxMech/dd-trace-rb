# typed: ignore

require 'datadog/appsec/contrib/integration'

require 'datadog/appsec/contrib/rails/configuration/settings'
require 'datadog/appsec/contrib/rails/patcher'
require 'datadog/appsec/contrib/rails/request_middleware'

module Datadog
  module AppSec
    module Contrib
      module Rails
        # Description of Rails integration
        class Integration
          include Datadog::AppSec::Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('3.2.0')

          register_as :rails, auto_patch: false

          def self.version
            Gem.loaded_specs['rails'] && Gem.loaded_specs['rails'].version
          end

          def self.loaded?
            !defined?(::Rails).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
          end

          def self.auto_instrument?
            true
          end

          def default_configuration
            Configuration::Settings.new
          end

          def patcher
            Patcher
          end
        end
      end
    end
  end
end
