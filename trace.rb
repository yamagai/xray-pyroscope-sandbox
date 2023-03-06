require 'rubygems'
require 'bundler/setup'
# Require otel-ruby
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp/exporter'
require 'opentelemetry/propagator/xray'
require 'pyroscope'

Pyroscope.configure do |config|
  config.application_name = "pyroscope"
  config.server_address   = "localhoge"
end

OpenTelemetry::SDK.configure do |c|
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: "localhost"
      )
    )
  )
  require 'pyroscope/otel'
  c.add_span_processor Pyroscope::Otel::SpanProcessor.new(
    "hogehoge.cpu",
    "localhost"
  )
  c.id_generator = OpenTelemetry::Propagator::XRay::IDGenerator
  c.propagators = [OpenTelemetry::Propagator::XRay::TextMapPropagator.new]
end


class Hoge
  @@tracer = OpenTelemetry.tracer_provider.tracer('hogehoge')
  @@carrier = {}
  @@root_span = nil

  def self.with_create_root_span(&block)
    begin
      span = @@tracer.start_root_span("root")
      span.set_attribute("request_id", "111111111111111")
      @@root_span = span
      OpenTelemetry::Trace.with_span(span) do
        OpenTelemetry.propagation.inject(@@carrier)
        block.call if block_given?
      end
    rescue => e
      span&.record_exception(e)
      span&.status = Status.error("DsTrace Unhandled exception of type: #{e.class}")
    end
  end

  def self.with_create_span(delete_root_span: false, &block)
    begin
      parent = OpenTelemetry.propagation.extract(@@carrier)
      span = @@tracer.start_span("child", with_parent: parent)
      OpenTelemetry::Trace.with_span(span, &block)
    rescue => e
      span&.record_exception(e)
      span&.status = Status.error("DsTrace Unhandled exception of type: #{e.class}")
    ensure
      span&.finish
      @@root_span&.finish if delete_root_span
    end
  end
end


Hoge.with_create_root_span do
  p "do something root"
end

Hoge.with_create_span(delete_root_span: true) do
  p "do something"
  # Hoge.with_create_span do
  #   p "do something2"
  # end
end


