# frozen_string_literal: true

require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "shows the sign-up form" do
    get new_registration_path

    assert_response :success
    assert_select "h1", "Create an account"
  end

  test "creates an account and signs the person in" do
    assert_difference [ "User.count", "Household.count" ], 1 do
      post registration_path, params: {
        user: { email_address: "fresh@example.com", password: "correct horse", password_confirmation: "correct horse" }
      }
    end

    assert_redirected_to dashboard_path
    follow_redirect!

    assert_response :success
  end

  test "redisplays the form with errors instead of signing in" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        user: { email_address: "bad", password: "short", password_confirmation: "short" }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".errors"
  end
end
