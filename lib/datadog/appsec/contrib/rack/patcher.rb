# typed: ignore

require 'datadog/appsec/contrib/patcher'
require 'datadog/appsec/contrib/rack/integration'
require 'datadog/appsec/contrib/rack/gateway/watcher'

module Datadog
  module AppSec
    module Contrib
      module Rack
        # Patcher for Rack integration
        module Patcher
          include Datadog::AppSec::Contrib::Patcher

          module_function

          def patched?
            Patcher.instance_variable_get(:@patched) # TODO: Patcher.flag_patched
          end

          def target_version
            Integration.version
          end

          def patch
            Gateway::Watcher.watch
            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
