module PrometheusMetrics
  extend ActiveSupport::Concern

  private
  def increment_metric(metric_name, labels: {}, value: nil)
    registry = Prometheus::Client.registry
    metric = registry.get(metric_name)
    return unless metric

    # Histogram uses observe, counters use increment
    if metric.is_a?(Prometheus::Client::Histogram)
      metric.observe(value, labels: labels) if value
    else
      metric.increment(labels: labels)
    end
  rescue => e
    Rails.logger.error "Error updating metric #{metric_name}: #{e.message}"
  end

  def group_labels(group_id, group_name)
    {
      group_id: group_id.to_s,
      group_name: sanitize_label(group_name)
    }
  end

  # Sanitize labels to avoid Prometheus label issues
  def sanitize_label(label)
    return "unknown" if label.nil? || label.empty?
    label.to_s.gsub(/[^a-zA-Z0-9_\-]/, "_")[0..63]
  end

  def increment_messages_processed(group_id, group_name)
    increment_metric(:telegram_bot_messages_processed, labels: group_labels(group_id, group_name))
  end

  def increment_spam_detected(group_id, group_name)
    increment_metric(:telegram_bot_spam_messages_detected, labels: group_labels(group_id, group_name))
  end

  def increment_message_processing_time(duration, group_id, group_name)
    increment_metric(
      :telegram_bot_message_processing_time,
      labels: group_labels(group_id, group_name),
      value: duration
    )
  end

  def increment_whitelisted_messages(group_id, group_name)
    increment_metric(:telegram_bot_whitelisted_messages, labels: group_labels(group_id, group_name))
  end

  def increment_processing_errors(group_id, group_name, error_type)
    increment_metric(
      :telegram_bot_processing_errors,
      labels: group_labels(group_id, group_name).merge(error_type: error_type)
    )
  end

  def increment_command_counter(command)
    increment_metric(:telegram_bot_command_count, labels: { command: command })
  end
end
