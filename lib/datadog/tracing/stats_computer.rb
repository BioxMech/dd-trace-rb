module Datadog
  module Tracing
    # TODO: class description
    class StatsComputer
      def self.perform(trace_segment)
        new(
          trace_segment.spans.collect { |s| s.__send__(:top_level?) },
          origin: trace_segment.origin
        ).perform
      end

      def initialize(spans, origin:)
        @spans = spans
        @origin = origin
      end

      def perform
        # TODO: How to make a thread-safe singleton
        repository = StatsRepository.new

        candidates.each do |span|
          bucket_size_ns = 10 * 1e9
          bucket_time_ns = span.end_time_nano - (span.end_time_nano % bucket_size_ns)

          agg_key = [
            span.name,
            span.service,
            span.resource,
            span.type,
            span.status,
            @origin == 'synthetics'
          ]

          repository.find_by(bucket_time_ns, agg_key).update!(span)
        end
      end
    end

    # TODO: description
    class Stats
      attr_reader :hits, :top_level_hits, :duration, :errs, :err_distribution, :ok_distribution

      def initialize
        @hits = 0
        @top_level_hits = 0
        @duration = 0
        @errs = 0
        @err_distribution = [] # DDSketch
        @ok_distribution  = [] # DDSketch
      end

      def update!(span)
        @hits += 1
        @duration += span.duration_nano
        @top_level_hits += 1 if span.__send__(:top_level?)

        if span.error?
          @errors += 1
          @err_distribution << span.duration_nano
        else
          @ok_distribution << span.duration_nano
        end
      end
    end

    class StatsRepository
      attr_reader :data

      def initialize
        @data = Hash.new do |hash, key|
          hash[key] = Hash.new { |nested_hash, k| nested_hash[k] = Stats.new }
        end
      end

      def find_by(k1, k2)
        @data[k1][k2]
      end

      def flush!
        # TODO: serialize & send request
        @data.clear
      end
    end
  end
end
