require "prometheus/client"
require "prometheus/client/data_stores/direct_file_store"

# Use file store to persist metrics across processes
Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(dir: Rails.root.join("tmp", "prometheus"))

# Define custom metrics for the Telegram bot
module TelegramBotMetrics
  # Counter for command usage (already has labels)
  COMMAND_COUNT = Prometheus::Client::Counter.new(
    :telegram_bot_command_count,
    docstring: "Number of times each command is used",
    labels: [ :command ]
  )

  # Counter for messages processed per group
  MESSAGES_PROCESSED = Prometheus::Client::Counter.new(
    :telegram_bot_messages_processed,
    docstring: "Number of messages processed by the bot",
    labels: [ :group_id, :group_name ]
  )

  # Counter for spam messages detected per group
  SPAM_MESSAGES_DETECTED = Prometheus::Client::Counter.new(
    :telegram_bot_spam_messages_detected,
    docstring: "Number of spam messages detected and handled",
    labels: [ :group_id, :group_name ]
  )

  # Histogram for message processing time per group
  MESSAGE_PROCESSING_TIME = Prometheus::Client::Histogram.new(
    :telegram_bot_message_processing_time,
    docstring: "Time spent processing messages in seconds",
    labels: [ :group_id, :group_name ],
    buckets: [ 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0 ]
  )

  # Additional metrics for per-group insights
  WHITELISTED_MESSAGES = Prometheus::Client::Counter.new(
    :telegram_bot_whitelisted_messages,
    docstring: "Number of messages skipped due to whitelist",
    labels: [ :group_id, :group_name ]
  )

  PROCESSING_ERRORS = Prometheus::Client::Counter.new(
    :telegram_bot_processing_errors,
    docstring: "Number of errors during message processing",
    labels: [ :group_id, :group_name, :error_type ]
  )

  # Register metrics with the default registry
  PROMETHEUS_REGISTRY = Prometheus::Client.registry
  PROMETHEUS_REGISTRY.register(COMMAND_COUNT)
  PROMETHEUS_REGISTRY.register(MESSAGES_PROCESSED)
  PROMETHEUS_REGISTRY.register(SPAM_MESSAGES_DETECTED)
  PROMETHEUS_REGISTRY.register(MESSAGE_PROCESSING_TIME)
  PROMETHEUS_REGISTRY.register(WHITELISTED_MESSAGES)
  PROMETHEUS_REGISTRY.register(PROCESSING_ERRORS)
end

# Make the metrics module globally accessible
Object.const_set(:TelegramBotMetrics, TelegramBotMetrics) if !Object.const_defined?(:TelegramBotMetrics)

# Monkey patch Prometheus::Client::Formats::Text to prevent invalid scrape output
# If DirectFileStore gets corrupted, values (like "sum") can be missing.
# The default formatter passes nil to a %s format string, resulting in an empty string
# and causing Prometheus to reject the entire scrape with an "INVALID" error.
require "prometheus/client/formats/text"

module PrometheusFormatPatch
  def metric(name, labels, value)
    # Default nil values to 0.0 so the text format always ends with a number
    super(name, labels, value || 0.0)
  end
end

Prometheus::Client::Formats::Text.singleton_class.prepend(PrometheusFormatPatch)
