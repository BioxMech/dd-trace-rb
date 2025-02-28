# typed: false

require 'datadog/tracing/contrib/integration'
require 'datadog/tracing/contrib/configuration/resolvers/pattern_resolver'
require 'datadog/tracing/contrib/mongodb/configuration/settings'
require 'datadog/tracing/contrib/mongodb/patcher'

module Datadog
  module Tracing
    module Contrib
      module MongoDB
        # Description of MongoDB integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('2.1.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :mongo, auto_patch: true

          def self.version
            Gem.loaded_specs['mongo'] && Gem.loaded_specs['mongo'].version
          end

          def self.loaded?
            !defined?(::Mongo::Monitoring::Global).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
          end

          def new_configuration
            Configuration::Settings.new
          end

          def patcher
            Patcher
          end

          def resolver
            @resolver ||= Contrib::Configuration::Resolvers::PatternResolver.new
          end
        end
      end
    end
  end
end
