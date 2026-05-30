Rails.application.configure do
  # We handle HTTP Basic Auth globally in ApplicationController,
  # so we disable Mission Control's built-in basic auth to prevent double-prompting.
  MissionControl::Jobs.http_basic_auth_enabled = false
end
