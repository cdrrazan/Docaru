# frozen_string_literal: true

require "test_helper"

# The vault key is stored twice, wrapped under a passphrase and under a recovery
# code, and this controller is the only thing that writes it. What it must never
# grow is a way to read either one.
class VaultKeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @household = households(:one)
  end

  # Opaque to the server by design, so the test values only have to be the right
  # shape: base64 for the wrappings, a 12-byte nonce base64'd for the ivs.
  def wrapping(suffix = "AAAA")
    {
      wrapped: "d3JhcHBlZGtleQ#{suffix}",
      wrapped_iv: "YWJjZGVmZ2hpamts",
      recovery_wrapped: "cmVjb3ZlcnlrZXk#{suffix}",
      recovery_wrapped_iv: "bW5vcHFyc3R1dnd4"
    }
  end

  test "requires authentication" do
    sign_out
    post vault_key_path, params: { vault_key: wrapping }, as: :json

    assert_response :redirect
  end

  test "stores both wrappings" do
    post vault_key_path, params: { vault_key: wrapping }, as: :json

    assert_response :created

    @household.reload

    assert_predicate @household, :vault_initialised?
    assert_predicate @household, :recovery_available?
    assert_equal wrapping[:wrapped], @household.wrapped_key
    assert_equal wrapping[:recovery_wrapped], @household.recovery_wrapped_key
  end

  # Creating a second key over the top of the first would orphan every scan the
  # household already has, with no way to get them back.
  test "refuses to overwrite an existing key through create" do
    post vault_key_path, params: { vault_key: wrapping }, as: :json
    post vault_key_path, params: { vault_key: wrapping("BBBB") }, as: :json

    assert_response :conflict
    assert_equal wrapping[:wrapped], @household.reload.wrapped_key
  end

  test "rewrapping replaces both wrappings and stamps the recovery" do
    post vault_key_path, params: { vault_key: wrapping }, as: :json

    patch vault_key_path, params: { vault_key: wrapping("BBBB") }, as: :json

    assert_response :success

    @household.reload

    assert_equal wrapping("BBBB")[:wrapped], @household.wrapped_key
    # A used recovery code is a spent one, so the rewrap issues a fresh one.
    assert_equal wrapping("BBBB")[:recovery_wrapped], @household.recovery_wrapped_key
    assert_not_nil @household.recovery_used_at
  end

  test "cannot rewrap a vault that does not exist yet" do
    patch vault_key_path, params: { vault_key: wrapping }, as: :json

    assert_response :not_found
  end

  test "rejects a wrapping that is not base64" do
    post vault_key_path, params: { vault_key: wrapping.merge(wrapped: "not base64!") }, as: :json

    assert_response :unprocessable_content
    assert_not_predicate @household.reload, :vault_initialised?
  end

  test "rejects a nonce of the wrong length" do
    post vault_key_path, params: { vault_key: wrapping.merge(wrapped_iv: "c2hvcnQ=") }, as: :json

    assert_response :unprocessable_content
  end

  # Scoped through the household established by Authentication, so one
  # household's key cannot be written by another's session.
  test "writes only to the signed-in household" do
    post vault_key_path, params: { vault_key: wrapping }, as: :json

    assert_predicate households(:one).reload, :vault_initialised?
    assert_not_predicate households(:two).reload, :vault_initialised?
  end

  # The salts are not secrets — they exist so one precomputed attack cannot be
  # reused against every household — but they must differ from each other, or
  # the two wrappings would be derived identically from different inputs.
  test "the passphrase and recovery salts are distinct" do
    assert_not_equal @household.vault_salt!, @household.recovery_salt!
  end
end
