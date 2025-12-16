require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module TelegramSpamSniperBot
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    config.items_per_page =  5
    config.max_spam_preview_length =  500
    config.max_spam_preview_button_length =  10
    # a user will be banned if send spam message >= 3 times
    config.spam_ban_threshold =  3
    # Delete the warning message in x minutes to keep chat clean
    config.delete_message_delay = 5
    # Spam blocked probability threshold
    config.probability_threshold = 0.94
    config.chinese_space_spam_threshold = 0.8
    # It should skip inspecting for messages sent on behalf of a channel (channel broadcasts)
    # But these blacklist groups already utilize this bot to inspect channel
    # broadcast message (I know, strange usecase), so inspect message
    # from these group as before
    config.channel_broadcast_blacklist = [ -1002133460865, -1002118991610 ]
    config.short_message_word_threshold = 3
  end
end
