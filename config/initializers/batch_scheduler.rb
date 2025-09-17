Rails.application.config.after_initialize do
  BatchScheduler.instance.start
  at_exit { BatchScheduler.instance.stop }
end
