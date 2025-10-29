require "prometheus/client"
require "prometheus/client/data_stores/direct_file_store"

# Use file store to persist metrics across processes
Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(dir: Rails.root.join("tmp", "prometheus"))

# Define custom metrics for the Telegram bot
module TelegramBotMetrics
  # Counter for command usage
  COMMAND_COUNT = Prometheus::Client::Counter.new(
    :telegram_bot_command_count,
    docstring: "Number of times each command is used",
    labels: [ :command ]
  )

  # Counter for messages processed
  MESSAGES_PROCESSED = Prometheus::Client::Counter.new(
    :telegram_bot_messages_processed,
    docstring: "Number of messages processed by the bot"
  )

  # Counter for spam messages detected
  SPAM_MESSAGES_DETECTED = Prometheus::Client::Counter.new(
    :telegram_bot_spam_messages_detected,
    docstring: "Number of spam messages detected and handled"
  )

  # Histogram for message processing time
  MESSAGE_PROCESSING_TIME = Prometheus::Client::Histogram.new(
    :telegram_bot_message_processing_time,
    docstring: "Time spent processing messages",
    buckets: [ 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0 ]
  )

  # Register metrics with the default registry
  PROMETHEUS_REGISTRY = Prometheus::Client.registry
  PROMETHEUS_REGISTRY.register(COMMAND_COUNT)
  PROMETHEUS_REGISTRY.register(MESSAGES_PROCESSED)
  PROMETHEUS_REGISTRY.register(SPAM_MESSAGES_DETECTED)
  PROMETHEUS_REGISTRY.register(MESSAGE_PROCESSING_TIME)
end

# Make the metrics module globally accessible
Object.const_set(:TelegramBotMetrics, TelegramBotMetrics) if !Object.const_defined?(:TelegramBotMetrics)
