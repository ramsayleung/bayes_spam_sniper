ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

module ActionDispatch
  class IntegrationTest
    def get(uri, **args)
      super(uri, **with_auth(args))
    end

    def post(uri, **args)
      super(uri, **with_auth(args))
    end

    def put(uri, **args)
      super(uri, **with_auth(args))
    end

    def patch(uri, **args)
      super(uri, **with_auth(args))
    end

    def delete(uri, **args)
      super(uri, **with_auth(args))
    end

    private

    def with_auth(args)
      username = ENV.fetch("ADMIN_USERNAME") { Rails.application.credentials.dig(:admin, :username) }
      password = ENV.fetch("ADMIN_PASSWORD") { Rails.application.credentials.dig(:admin, :password) }

      return args if username.blank? || password.blank?

      args[:headers] ||= {}
      args[:headers]["HTTP_AUTHORIZATION"] = ActionController::HttpAuthentication::Basic.encode_credentials(username, password)
      args
    end
  end
end
