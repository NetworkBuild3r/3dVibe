ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    include ActiveSupport::Testing::TimeHelpers

    def fixture_library_root
      Rails.root.join("test/fixtures/files/library").to_s
    end

    def create_owner!(email: "owner@example.test", password: "secret123")
      User.create!(email: email, display_name: "Owner", password: password, password_confirmation: password)
    end

    def auth_header(user)
      token = user.access_tokens.create!(expires_at: 1.day.from_now)
      { "Authorization" => "Bearer #{token.token}" }
    end
  end
end
