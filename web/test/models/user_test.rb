# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")

    assert_equal("downcased@example.com", user.email_address)
  end

  test "register creates the user and their household together" do
    user = User.register(email_address: "new@example.com", password: "correct horse", password_confirmation: "correct horse")

    assert_predicate user, :persisted?
    assert_predicate user.household, :persisted?
    assert_equal "free", user.household.plan
  end

  test "register names the household after the person" do
    user = User.register(email_address: "a@example.com", password: "correct horse",
                         password_confirmation: "correct horse", name: "Rajan Bhattarai")

    assert_equal "Rajan's household", user.household.name
  end

  test "register falls back to the email local part for a household name" do
    user = User.register(email_address: "sunita@example.com", password: "correct horse",
                         password_confirmation: "correct horse")

    assert_equal "Sunita's household", user.household.name
  end

  test "register honours an explicit household name" do
    user = User.register(email_address: "b@example.com", password: "correct horse",
                         password_confirmation: "correct horse", household_name: "Kathmandu flat")

    assert_equal "Kathmandu flat", user.household.name
  end

  # A failed registration must not leave an orphan household behind.
  test "register persists nothing when the user is invalid" do
    assert_no_difference [ "User.count", "Household.count" ] do
      user = User.register(email_address: "not an email", password: "correct horse",
                           password_confirmation: "correct horse")

      assert_not_predicate user, :persisted?
    end
  end

  test "rejects a mismatched confirmation" do
    assert_no_difference "User.count" do
      User.register(email_address: "c@example.com", password: "correct horse", password_confirmation: "different")
    end
  end

  test "rejects a short password" do
    assert_no_difference "User.count" do
      User.register(email_address: "d@example.com", password: "short", password_confirmation: "short")
    end
  end

  test "rejects a duplicate email address" do
    assert_no_difference "User.count" do
      User.register(email_address: users(:one).email_address, password: "correct horse",
                    password_confirmation: "correct horse")
    end
  end
end
