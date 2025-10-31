class MetricsService
  # Get spam detection rate for a specific group
  def self.spam_detection_rate(group_id: nil)
    if group_id
      messages_processed = get_counter_value_for_group(:telegram_bot_messages_processed, group_id)
      spam_detected = get_counter_value_for_group(:telegram_bot_spam_messages_detected, group_id)
    else
      messages_processed = get_counter_value(:telegram_bot_messages_processed)
      spam_detected = get_counter_value(:telegram_bot_spam_messages_detected)
    end

    return 0.0 if messages_processed == 0

    (spam_detected.to_f / messages_processed * 100).round(2)
  end

  # Get total counter value across all groups
  def self.get_counter_value(metric_name)
    registry = Prometheus::Client.registry
    counter = registry.get(metric_name)
    return 0 unless counter

    begin
      values = counter.values
      return 0 if values.empty?

      # Sum all label combinations
      values.values.sum.to_f
    rescue => e
      Rails.logger.error "Error reading counter #{metric_name}: #{e.message}"
      0
    end
  end

  # Get counter value for a specific group
  def self.get_counter_value_for_group(metric_name, group_id)
    registry = Prometheus::Client.registry
    counter = registry.get(metric_name)
    return 0 unless counter

    begin
      values = counter.values
      return 0 if values.empty?

      # Sum values matching the group_id
      values.select { |labels, _| labels[:group_id] == group_id.to_s }
        .values
        .sum
        .to_f
    rescue => e
      Rails.logger.error "Error reading counter #{metric_name} for group #{group_id}: #{e.message}"
      0
    end
  end

  # Get metrics for all groups
  def self.metrics_by_group
    registry = Prometheus::Client.registry

    messages_counter = registry.get(:telegram_bot_messages_processed)
    spam_counter = registry.get(:telegram_bot_spam_messages_detected)

    return {} unless messages_counter && spam_counter

    groups = {}

    messages_counter.values.each do |labels, count|
      group_id = labels[:group_id]
      group_name = labels[:group_name]

      groups[group_id] ||= {
        group_id: group_id,
        group_name: group_name,
        messages_processed: 0,
        spam_detected: 0
      }

      groups[group_id][:messages_processed] += count.to_f
    end

    spam_counter.values.each do |labels, count|
      group_id = labels[:group_id]

      groups[group_id] ||= {
        group_id: group_id,
        group_name: labels[:group_name],
        messages_processed: 0,
        spam_detected: 0
      }

      groups[group_id][:spam_detected] += count.to_f
    end

    # Calculate spam rate for each group
    groups.each do |group_id, metrics|
      if metrics[:messages_processed] > 0
        metrics[:spam_rate_percent] = (metrics[:spam_detected] / metrics[:messages_processed] * 100).round(2)
      else
        metrics[:spam_rate_percent] = 0.0
      end
    end

    groups
  end

  # Get command usage statistics
  def self.command_usage_stats
    registry = Prometheus::Client.registry
    counter = registry.get(:telegram_bot_command_count)
    return {} unless counter

    begin
      counter.values.transform_keys { |labels| labels[:command] }
        .transform_values(&:to_f)
    rescue => e
      Rails.logger.error "Error reading command stats: #{e.message}"
      {}
    end
  end

  # Get all current metrics
  def self.current_metrics
    {
      total_messages_processed: get_counter_value(:telegram_bot_messages_processed),
      total_spam_detected: get_counter_value(:telegram_bot_spam_messages_detected),
      overall_spam_rate_percent: spam_detection_rate,
      command_usage: command_usage_stats,
      by_group: metrics_by_group
    }
  end
end
