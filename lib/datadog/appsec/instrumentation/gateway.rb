# typed: true

module Datadog
  module AppSec
    # Instrumentation for AppSec
    module Instrumentation
      # Instrumentation gateway implementation
      class Gateway
        def initialize
          @middlewares = Hash.new { |h, k| h[k] = [] }
        end

        def push(name, env, &block)
          block ||= -> {}

          middlewares = @middlewares[name]

          return [block.call, nil] if middlewares.empty?

          wrapped = lambda do |_env|
            [block.call, nil]
          end

          # TODO: handle exceptions, except for wrapped
          stack = middlewares.reverse.reduce(wrapped) do |next_, middleware|
            lambda do |env_|
              middleware.call(next_, env_)
            end
          end

          stack.call(env)
        end

        def watch(name, &block)
          @middlewares[name] << block
        end
      end

      def self.gateway
        @gateway ||= Gateway.new # TODO: not thread safe
      end
    end
  end
end
