module Datadog
  module Tracing
    module Sampling
      module Span
        # Applies a set of rules to a span.
        # This class is used to apply sampling operations to all
        # spans in the tracer.
        #
        # Span sampling is distinct from trace sampling: span
        # sampling can keep a span that is part of tracer that was
        # rejected by trace sampling.
        #
        # This class only applies operations to spans that are part
        # of traces that were rejected by trace sampling. There's no
        # reason to try to sample spans that are already kept by
        # the trace sampler.
        class Sampler
          # Receives sampling rules to apply to individual spans.
          #
          # @param [Array<Datadog::Tracing::Sampling::Span::Rule>] rules list of rules to apply to spans
          def initialize(rules = [])
            @rules = rules
          end

          # Applies sampling rules to the span if the trace has been rejected.
          #
          # If multiple rules match, only the first one is applied.
          #
          # @param [Datadog::Tracing::TraceOperation] trace_op trace for the provided span
          # @param [Datadog::Tracing::SpanOperation] span_op Span to apply sampling rules
          # @return [void]
          def sample!(trace_op, span_op)
            return if trace_op.sampled?

            # Return as soon as one rule returns non-nil
            # DEV: `all?{|x|x.nil?}` is faster than `any?{|x|!x.nil?}`
            @rules.all? do |rule|
              rule.sample!(span_op).nil?
            end
          end
        end
      end
    end
  end
end
