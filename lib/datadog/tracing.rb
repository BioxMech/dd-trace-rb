module Datadog
  # Datadog APM tracing public API.
  #
  # The Datadog teams ensures that public methods in this module
  # only receive backwards compatible changes, and breaking changes
  # will only occur in new major versions releases.
  # @public_api
  module Tracing
    class << self
      # (see Datadog::Tracer#trace)
      # @public_api
      def trace(name, continue_from: nil, **span_options, &block)
        tracer.trace(name, continue_from: continue_from, **span_options, &block)
      end

      # (see Datadog::Tracer#continue_trace!)
      # @public_api
      def continue_trace!(digest, &block)
        tracer.continue_trace!(digest, &block)
      end

      # The currently active {Datadog::Tracer} instance.
      #
      # The instance returned can change throughout the lifetime of the application.
      # This means it is not advisable to cache it.
      #
      # The trace can be configured through {.configure},
      # through {Datadog::Configuration::Settings::DSL::Tracer} options.
      #
      # TODO: I think this next paragraph can be better written.
      #
      # Most of the functionality available through the {.tracer} instance is
      # also available in public methods in the {Datadog::Tracing} module.
      # It is preferable to use the public methods in the {Datadog::Tracing} when possible
      # as {Datadog::Tracing} strongly defines the tracing public API, and thus
      # we strive to no introduce breaking changes to {Datadog::Tracing} methods.
      #
      # @return [Datadog::Tracer] the active tracer
      # @!attribute [r] tracer
      # @public_api
      def tracer
        components.tracer
      end

      # The tracer's internal logger instance.
      # All tracing log output is handled by this object.
      #
      # The logger can be configured through {.configure},
      # through {Datadog::Configuration::Settings::DSL::Logger} options.
      #
      # @!attribute [r] logger
      # @public_api
      def logger
        Datadog.logger
      end

      # Current tracer configuration.
      #
      # To modify the configuration, use {.configure}.
      #
      # @return [Datadog::Configuration::Settings]
      # @!attribute [r] configuration
      # @public_api
      def configuration
        Datadog.configuration
      end

      # Apply configuration changes to `ddtrace`. An example of a {.configure} call:
      # ```
      # Datadog.configure do |c|
      #   c.sampling.default_rate = 1.0
      #   c.use :aws
      #   c.use :rails
      #   c.use :sidekiq
      #   # c.diagnostics.debug = true # Enables debug output
      # end
      # ```
      #
      # Because many configuration changes require restarting internal components,
      # invoking {.configure} is the only safe way to change `ddtrace` configuration.
      #
      # Successive calls to {.configure} maintain the previous configuration values:
      # configuration is additive between {.configure} calls.
      #
      # The yielded configuration `c` comes pre-populated from environment variables, if
      # any are applicable.
      #
      # See {Datadog::Configuration::Settings} for all available options, defaults, and
      # available environment variables for configuration.
      #
      # @yieldparam [Datadog::Configuration::Settings] c the mutable configuration object
      # @return [void]
      # @public_api
      def configure(&block)
        Datadog.configure(&block)
      end

      # (see Datadog::Tracer#active_trace)
      # @public_api
      def active_trace
        tracer.active_trace
      end

      # (see Datadog::Tracer#active_span)
      # @public_api
      def active_span
        tracer.active_span
      end

      # (see Datadog::TraceSegment#keep!)
      # If no trace is active, no action is taken.
      # @public_api
      def keep!
        trace = active_trace
        active_trace.keep! if trace
      end

      # (see Datadog::TraceSegment#reject!)
      # If no trace is active, no action is taken.
      # @public_api
      def reject!
        trace = active_trace
        active_trace.reject! if trace
      end

      # (see Datadog::Tracer#active_correlation)
      # @public_api
      def correlation
        tracer.active_correlation
      end

      # Textual representation of {.correlation}, which can be
      # added to individual log lines in order to correlate them with the active
      # trace.
      #
      # Example:
      #
      # ```
      # MyLogger.log("#{Datadog::Tracing.log_correlation}] My log message")
      # # dd.env=prod dd.service=billing dd.version=13.8 dd.trace_id=545847825299552251 dd.span_id=711755234730770098 My log message
      # ```
      #
      # @return [String] correlation information
      # @public_api
      def log_correlation
        correlation.to_log_format
      end

      # Gracefully shuts down the tracer.
      #
      # The public tracing API will still respond to method calls as usual
      # but might not internally perform the expected internal work after shutdown.
      #
      # This avoids errors being raised across the host application
      # during shutdown while allowing for the graceful decommission of resources.
      #
      # {.shutdown!} cannot be reversed.
      # @public_api
      def shutdown!
        components.shutdown!
      end

      # The global integration registry.
      #
      # This registry holds a reference to all integrations available
      # to the tracer.
      #
      # Integrations registered in the {.registry} can be activated as follows:
      #
      # ```
      # Datadog.configure do |c|
      #   c.use :my_registered_integration, **my_options
      # end
      # ```
      #
      # New integrations can be registered by implementing the {Datadog::Contrib::Integration} interface.
      #
      # @return [Datadog::Contrib::Registry]
      # @!attribute [r] registry
      # @public_api
      def registry
        Datadog::Contrib::REGISTRY
      end

      private

      # DEV: components hosts both tracing and profiling inner objects today
      def components
        Datadog.send(:components)
      end
    end
  end
end
