# typed: false
require 'logger'
require 'ddtrace/configuration/base'

require 'ddtrace/ext/analytics'
require 'ddtrace/ext/distributed'
require 'ddtrace/ext/environment'
require 'ddtrace/ext/profiling'
require 'ddtrace/ext/sampling'
require 'ddtrace/ext/test'

module Datadog
  module Configuration
    # Global configuration settings for the trace library.
    # rubocop:disable Metrics/ClassLength
    class Settings
      include Base

      # @!visibility private
      def initialize(*_)
        super

        # WORKAROUND: The values for services, version, and env can get set either directly OR as a side effect of
        # accessing tags (reading or writing). This is of course really confusing and error-prone, e.g. in an app
        # WITHOUT this workaround where you define `DD_TAGS=env:envenvtag,service:envservicetag,version:envversiontag`
        # and do:
        #
        # puts Datadog.configuration.instance_exec { "#{service} #{env} #{version}" }
        # Datadog.configuration.tags
        # puts Datadog.configuration.instance_exec { "#{service} #{env} #{version}" }
        #
        # the output will be:
        #
        # [empty]
        # envservicetag envenvtag envversiontag
        #
        # That is -- the proper values for service/env/version are only set AFTER something accidentally or not triggers
        # the resolution of the tags.
        # This is really confusing, error prone, etc, so calling tags here is a really hacky but effective way to
        # avoid this. I could not think of a better way of fixing this issue without massive refactoring of tags parsing
        # (so that the individual service/env/version get correctly set even from their tags values, not as a side
        # effect). Sorry :(
        tags
      end

      # Legacy [App Analytics](https://docs.datadoghq.com/tracing/legacy_app_analytics/) configuration.
      #
      # @deprecated Use [Trace Retention and Ingestion](https://docs.datadoghq.com/tracing/trace_retention_and_ingestion/) controls.
      settings :analytics do
        # @default `DD_TRACE_ANALYTICS_ENABLED` environment variable, otherwise `nil`
        # @return [Boolean,nil]
        option :enabled do |o|
          o.default { env_to_bool(Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED, nil) }
          o.lazy
        end
      end

      # Profiler API key.
      # @default `DD_API_KEY` environment variable, otherwise `nil`
      # @return [String,nil]
      option :api_key do |o|
        o.default { ENV.fetch(Ext::Environment::ENV_API_KEY, nil) }
        o.lazy
      end

      # Internal tracer diagnostic settings.
      #
      # Enabling these surfaces debug information that can be helpful to
      # diagnose issues related to the tracer internals.
      settings :diagnostics do
        # Outputs all spans created by the host application to `Datadog.logger`.
        #
        # **This option is very verbose!** It's only recommended for non-production
        # environments.
        #
        # This option is helpful when trying to understand what information the
        # tracer is sending to the Agent or backend.
        # @default `DD_TRACE_DEBUG` environment variable, otherwise `false`
        # @return [Boolean]
        option :debug do |o|
          o.default { env_to_bool(Datadog::Ext::Diagnostics::DD_TRACE_DEBUG, false) }
          o.lazy
          o.on_set do |enabled|
            # Enable rich debug print statements.
            # We do not need to unnecessarily load 'pp' unless in debugging mode.
            require 'pp' if enabled
          end
        end

        # Internal tracer {Datadog::Statsd} metrics collection.
        #
        # The list of metrics collected can be found in {Datadog::Ext::Diagnostics::Health::Metrics}.
        settings :health_metrics do
          # Enable health metrics collection.
          #
          # @default `DD_HEALTH_METRICS_ENABLED` environment variable, otherwise `false`
          # @return [Boolean]
          option :enabled do |o|
            o.default { env_to_bool(Datadog::Ext::Diagnostics::Health::Metrics::ENV_ENABLED, false) }
            o.lazy
          end

          # {Datadog::Statsd} instance to collect health metrics.
          #
          # If `nil`, health metrics creates a new {Datadog::Statsd} client with default agent configuration.
          # @default `nil`
          # @return [Datadog::Statsd,nil]
          option :statsd
        end

        # Tracer startup debug log statement configuration.
        settings :startup_logs do
          # Enable startup logs collection.
          #
          # If `nil`, defaults to logging startup logs when `ddtrace` detects that the application
          # is *not* running in a development environment.
          #
          # @default `DD_TRACE_STARTUP_LOGS` environment variable, otherwise `nil`
          # @return [Boolean,nil]
          option :enabled do |o|
            # Defaults to nil as we want to know when the default value is being used
            o.default { env_to_bool(Datadog::Ext::Diagnostics::DD_TRACE_STARTUP_LOGS, nil) }
            o.lazy
          end
        end
      end

      # [Distributed Tracing](https://docs.datadoghq.com/tracing/setup_overview/setup/ruby/#distributed-tracing) propagation
      # style configuration.
      #
      # The supported formats are:
      # * `Datadog`: Datadog propagation format, described by [Distributed Tracing](https://docs.datadoghq.com/tracing/setup_overview/setup/ruby/#distributed-tracing).
      # * `B3`: B3 Propagation using multiple headers, described by [openzipkin/b3-propagation](https://github.com/openzipkin/b3-propagation#multiple-headers).
      # * `B3 single header`: B3 Propagation using a single header, described by [openzipkin/b3-propagation](https://github.com/openzipkin/b3-propagation#single-header).
      #
      settings :distributed_tracing do
        # An ordered list of what data propagation styles the tracer will use to extract distributed tracing propagation
        # data from incoming requests and messages.
        #
        # The tracer will try to find distributed headers in the order they are present in the list provided to this option.
        # The first format to have valid data present will be used.
        #
        # @default `DD_PROPAGATION_STYLE_EXTRACT` environment variable (comma-separated list), otherwise `['Datadog','B3','B3 single header']`.
        # @return [Array<String>]
        option :propagation_extract_style do |o|
          o.default do
            # Look for all headers by default
            env_to_list(Ext::DistributedTracing::PROPAGATION_STYLE_EXTRACT_ENV,
                        [Ext::DistributedTracing::PROPAGATION_STYLE_DATADOG,
                         Ext::DistributedTracing::PROPAGATION_STYLE_B3,
                         Ext::DistributedTracing::PROPAGATION_STYLE_B3_SINGLE_HEADER])
          end

          o.lazy
        end

        # The data propagation styles the tracer will use to inject distributed tracing propagation
        # data into outgoing requests and messages.
        #
        # The tracer will inject data from all styles specified in this option.
        #
        # @default `DD_PROPAGATION_STYLE_INJECT` environment variable (comma-separated list), otherwise `['Datadog']`.
        # @return [Array<String>]
        option :propagation_inject_style do |o|
          o.default do
            env_to_list(
              Ext::DistributedTracing::PROPAGATION_STYLE_INJECT_ENV,
              [Ext::DistributedTracing::PROPAGATION_STYLE_DATADOG] # Only inject Datadog headers by default
            )
          end

          o.lazy
        end
      end

      # The `env` tag in Datadog. Use it to separate out your staging, development, and production environments.
      # @see https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging
      # @default `DD_ENV` environment variable, otherwise `nil`
      # @return [String,nil]
      option :env do |o|
        # NOTE: env also gets set as a side effect of tags. See the WORKAROUND note in #initialize for details.
        o.default { ENV.fetch(Ext::Environment::ENV_ENVIRONMENT, nil) }
        o.lazy
      end

      # Automatic correlation between tracing and logging.
      # @see https://docs.datadoghq.com/tracing/setup_overview/setup/ruby/#trace-correlation
      # @return [Boolean]
      option :log_injection do |o|
        o.default { env_to_bool(Ext::Correlation::ENV_LOGS_INJECTION_ENABLED, true) }
        o.lazy
      end

      # Internal `Datadog.logger` configuration.
      #
      # This logger instance is only used internally by the gem.
      settings :logger do
        # The `Datadog.logger` object.
        #
        # Can be overwritten with a custom logger object that respects the
        # [built-in Ruby Logger](https://ruby-doc.org/stdlib-3.0.1/libdoc/logger/rdoc/Logger.html)
        # interface.
        #
        # @return Logger::Severity
        option :instance do |o|
          o.on_set { |value| set_option(:level, value.level) unless value.nil? }
        end

        # Log level for `Datadog.logger`.
        # @see Logger::Severity
        # @return Logger::Severity
        option :level, default: ::Logger::INFO
      end

      # Datadog Profiler-specific configurations.
      #
      # @see https://docs.datadoghq.com/tracing/profiler/
      settings :profiling do
        # Enable profiling.
        #
        # @default `DD_PROFILING_ENABLED` environment variable, otherwise `false`
        # @return [Boolean]
        option :enabled do |o|
          o.default { env_to_bool(Ext::Profiling::ENV_ENABLED, false) }
          o.lazy
        end

        settings :exporter do
          option :transport
        end

        settings :advanced do
          # This should never be reduced, as it can cause the resulting profiles to become biased.
          # The current default should be enough for most services, allowing 16 threads to be sampled around 30 times
          # per second for a 60 second period.
          option :max_events, default: 32768

          # Controls the maximum number of frames for each thread sampled. Can be tuned to avoid omitted frames in the
          # produced profiles. Increasing this may increase the overhead of profiling.
          option :max_frames do |o|
            o.default { env_to_int(Ext::Profiling::ENV_MAX_FRAMES, 400) }
            o.lazy
          end

          settings :endpoint do
            settings :collection do
              # When using profiling together with tracing, this controls if endpoint names
              # are gathered and reported together with profiles.
              #
              # @default `DD_PROFILING_ENDPOINT_COLLECTION_ENABLED` environment variable, otherwise `true`
              # @return [Boolean]
              option :enabled do |o|
                o.default { env_to_bool(Ext::Profiling::ENV_ENDPOINT_COLLECTION_ENABLED, true) }
                o.lazy
              end
            end
          end
        end

        settings :upload do
          option :timeout_seconds do |o|
            o.setter { |value| value.nil? ? 30.0 : value.to_f }
            o.default { env_to_float(Ext::Profiling::ENV_UPLOAD_TIMEOUT, 30.0) }
            o.lazy
          end
        end
      end

      option :report_hostname do |o|
        o.default { env_to_bool(Ext::NET::ENV_REPORT_HOSTNAME, false) }
        o.lazy
      end

      settings :runtime_metrics do
        # Enable runtime metrics.
        # @default `DD_RUNTIME_METRICS_ENABLED` environment variable, otherwise `false`
        # @return [Boolean]
        option :enabled do |o|
          o.default { env_to_bool(Ext::Runtime::Metrics::ENV_ENABLED, false) }
          o.lazy
        end

        option :opts, default: ->(_i) { {} }, lazy: true
        option :statsd
      end

      # Backwards compatibility for configuring runtime metrics e.g. `c.runtime_metrics enabled: true`
      def runtime_metrics(options = nil)
        settings = get_option(:runtime_metrics)
        return settings if options.nil?

        # If options were provided (old style) then raise warnings and apply them:
        # TODO: Raise deprecation warning
        settings.enabled = options[:enabled] if options.key?(:enabled)
        settings.statsd = options[:statsd] if options.key?(:statsd)
        settings
      end

      # @deprecated Use `runtime_metrics.enabled` instead.
      # @return [Boolean]
      option :runtime_metrics_enabled do |o|
        o.delegate_to { get_option(:runtime_metrics).enabled }
        o.on_set do |value|
          # TODO: Raise deprecation warning
          get_option(:runtime_metrics).enabled = value
        end
      end

      # Client-side sampling configuration.
      settings :sampling do
        # Default sampling rate for the tracer.
        #
        # If `nil`, the trace uses an automatic sampling strategy that tries to ensure
        # the collection of traces that are considered important (e.g. traces with an error, traces
        # for resources not seen recently).
        #
        # @default `DD_TRACE_SAMPLE_RATE` environment variable, otherwise `nil`.
        # @return [Float,nil]
        option :default_rate do |o|
          o.default { env_to_float(Ext::Sampling::ENV_SAMPLE_RATE, nil) }
          o.lazy
        end

        # Rate limit for number of spans per second.
        #
        # Spans created above the limit will contribute to service metrics, but won't
        # have their payload stored.
        #
        # @default `DD_TRACE_RATE_LIMIT` environment variable, otherwise 100.
        # @return [Numeric,nil]
        option :rate_limit do |o|
          o.default { env_to_float(Ext::Sampling::ENV_RATE_LIMIT, 100) }
          o.lazy
        end
      end

      # The `service` tag in Datadog. Use it to group related traces into a service.
      # @see https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging
      # @default `DD_SERVICE` environment variable, otherwise the program name (e.g. `'ruby'`, `'rails'`, `'pry'`)
      # @return [String]
      option :service do |o|
        # NOTE: service also gets set as a side effect of tags. See the WORKAROUND note in #initialize for details.
        o.default { ENV.fetch(Ext::Environment::ENV_SERVICE, Ext::Environment::FALLBACK_SERVICE_NAME) }
        o.lazy

        # There's a few cases where we don't want to use the fallback service name, so this helper allows us to get a
        # nil instead so that one can do
        # nice_service_name = Datadog.configure.service_without_fallback || nice_service_name_default
        o.helper(:service_without_fallback) do
          service_name = service
          service_name unless service_name.equal?(Ext::Environment::FALLBACK_SERVICE_NAME)
        end
      end

      # TODO: profiler related. Ask @ivoanjo what this is for.
      # @return [String,nil]
      option :site do |o|
        o.default { ENV.fetch(Ext::Environment::ENV_SITE, nil) }
        o.lazy
      end

      # Default tracing span tags.
      #
      # These tags are applied to every span.
      # @default `DD_TAGS` environment variable (in the format `'tag1:value1,tag2:value2'`), otherwise `{}`
      # @return [Hash<String,String>]
      option :tags do |o|
        o.default do
          tags = {}

          # Parse tags from environment
          env_to_list(Ext::Environment::ENV_TAGS).each do |tag|
            pair = tag.split(':')
            tags[pair.first] = pair.last if pair.length == 2
          end

          # Override tags if defined
          tags[Ext::Environment::TAG_ENV] = env unless env.nil?
          tags[Ext::Environment::TAG_VERSION] = version unless version.nil?

          tags
        end

        o.setter do |new_value, old_value|
          # Coerce keys to strings
          string_tags = new_value.collect { |k, v| [k.to_s, v] }.to_h

          # Cross-populate tag values with other settings

          self.env = string_tags[Ext::Environment::TAG_ENV] if env.nil? && string_tags.key?(Ext::Environment::TAG_ENV)

          if version.nil? && string_tags.key?(Ext::Environment::TAG_VERSION)
            self.version = string_tags[Ext::Environment::TAG_VERSION]
          end

          if service_without_fallback.nil? && string_tags.key?(Ext::Environment::TAG_SERVICE)
            self.service = string_tags[Ext::Environment::TAG_SERVICE]
          end

          # Merge with previous tags
          (old_value || {}).merge(string_tags)
        end

        o.lazy
      end

      # [Continuous Integration Visibility](https://docs.datadoghq.com/continuous_integration/) configuration.
      settings :test_mode do
        # Enable test mode. This allows the tracer to collect spans from test runs.
        #
        # It also prevents the tracer from collecting spans in a production environment. Only use in a test environment.
        #
        # @default `DD_TRACE_TEST_MODE_ENABLED` environment variable, otherwise `false`
        # @return [Boolean]
        option :enabled do |o|
          o.default { env_to_bool(Ext::Test::ENV_MODE_ENABLED, false) }
          o.lazy
        end

        # TODO: Remove this configuration.
        # TODO: It is not necessary, as it be configured by the default flushing trace configuration.
        option :trace_flush do |o|
          o.default { nil }
          o.lazy
        end

        # TODO: Remove this configuration.
        # TODO: It is not necessary, as it be configured by the default writer trace configuration.
        option :writer_options do |o|
          o.default { {} }
          o.lazy
        end
      end

      # The time provider used by the tracer. It must respect the interface of [Time](https://ruby-doc.org/core-3.0.1/Time.html).
      #
      # When testing, it can be helpful to use a different time provider.
      #
      # For [Timecop](https://rubygems.org/gems/timecop), for example, `->{ Time.now_without_mock_time }` allows the tracer to use the real wall time when time is frozen.
      # @default `->{ Time.now }`
      # @return [Proc<Time>]
      option :time_now_provider do |o|
        o.default { ::Time.now }

        o.on_set do |time_provider|
          Utils::Time.now_provider = time_provider
        end

        o.resetter do |_value|
          # TODO: Resetter needs access to the default value
          # TODO: to help reduce duplication.
          -> { ::Time.now }.tap do |default|
            Utils::Time.now_provider = default
          end
        end
      end

      # Tracer specific configurations.
      settings :tracer do
        # Enable trace collection and span generation.
        #
        # You can use this option to disable tracing without having to
        # remove the library as a whole.
        #
        # @default `DD_TRACE_ENABLED` environment variable, otherwise `true`
        # @return [Boolean]
        option :enabled do |o|
          o.default { env_to_bool(Datadog::Ext::Diagnostics::DD_TRACE_ENABLED, true) }
          o.lazy
        end
        option :hostname # TODO: Deprecate

        # A custom tracer instance.
        #
        # It must respected the contract of {Datadog::Tracer}.
        # It's recommended to inherit from {Datadog::Tracer} to ease the implementation
        # of a custom tracer.
        #
        # This option will not return the live tracer instance: it only holds a custom
        # tracing instance, if any. The live tracer instance can be found in {Datadog.tracer}.
        #
        # @default `nil`
        # @return [Object,nil]
        option :instance

        # Configures an alternative trace transport behavior, where
        # traces can be sent to the agent and backend before all spans
        # have finished.
        #
        # This is useful for long-running jobs or very large traces.
        #
        # The trace flame graph will display the partial trace as it is received and constantly
        # update with new spans as they are flushed.
        settings :partial_flush do
          # Enable partial trace flushing.
          #
          # @default `false`
          # @return [Boolean]
          option :enabled, default: false

          # Minimum number of finished spans required in a single unfinished trace before
          # the tracer will consider that trace for partial flushing.
          #
          # This option helps preserve a minimum amount of batching in the
          # flushing process, reducing network overhead.
          #
          # This threshold only applies to unfinished traces. Traces that have finished
          # are always flushed immediately.
          #
          # @default 500
          # @return [Boolean]
          option :min_spans_threshold, default: 500
        end

        option :port # TODO: Deprecate
        option :priority_sampling # TODO: Deprecate

        # A custom sampler instance.
        # The object must respect the {Datadog::Sampler} interface.
        # @default `nil`
        # @return [Object,nil]
        option :sampler
        option :transport_options, default: ->(_i) { {} }, lazy: true # TODO: Deprecate
        option :writer # TODO: Deprecate
        option :writer_options, default: ->(_i) { {} }, lazy: true # TODO: Deprecate
      end

      # The `version` tag in Datadog. Use it to enable [Deployment Tracking](https://docs.datadoghq.com/tracing/deployment_tracking/).
      # @see https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging
      # @default `DD_VERSION` environment variable, otherwise `nils`
      # @return [String,nil]
      option :version do |o|
        # NOTE: version also gets set as a side effect of tags. See the WORKAROUND note in #initialize for details.
        o.default { ENV.fetch(Ext::Environment::ENV_VERSION, nil) }
        o.lazy
      end
    end
  end
end
