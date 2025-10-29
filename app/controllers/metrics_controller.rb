class MetricsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def show
    # For DirectFileStore, we need to use the registry's format method directly
    # This is the correct approach for file-based storage
    registry = Prometheus::Client.registry

    # The marshal method is still the standard way for the text format
    require "prometheus/client/formats/text"

    begin
      metrics_text = Prometheus::Client::Formats::Text.marshal(registry)
      render plain: metrics_text, content_type: "text/plain; version=0.0.4"
    rescue NoMethodError, NameError => e
      # Fallback if marshal is not available
      Rails.logger.error "Prometheus marshal method not available: #{e.message}"
      render plain: "# Error: #{e.message}", status: 500, content_type: "text/plain"
    rescue => e
      Rails.logger.error "Error in metrics endpoint: #{e.message}\n#{e.backtrace.join("\n")}"
      render plain: "# Error: #{e.message}", status: 500, content_type: "text/plain"
    end
  end
end
