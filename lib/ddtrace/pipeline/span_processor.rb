# typed: true
module Datadog
  module Pipeline
    # SpanProcessor
    # @public_api
    class SpanProcessor
      def initialize(operation = nil, &block)
        callable = operation || block

        raise(ArgumentError) unless callable.respond_to?(:call)

        @operation = operation || block
      end

      # @!visibility private
      def call(trace)
        trace.spans.each do |span|
          @operation.call(span) rescue next
        end

        trace
      end
    end
  end
end
