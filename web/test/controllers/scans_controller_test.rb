# frozen_string_literal: true

require "test_helper"

class ScansControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  # Same construction as the parser test: valid by arithmetic, not by copying a
  # real passport into the repository.
  def valid_mrz
    line1 = "P<NPLBHATTARAI<<RAJAN".ljust(44, "<")
    number = "12AB34567"
    body = number + MachineReadableZone.check_digit(number).to_s + "NPL" +
           "900115" + MachineReadableZone.check_digit("900115").to_s + "M" +
           "310220" + MachineReadableZone.check_digit("310220").to_s + ("<" * 14) + "<"
    composite = body[0, 10] + body[13, 7] + body[21, 22]
    [ line1, body + MachineReadableZone.check_digit(composite).to_s ].join("\n")
  end

  test "requires authentication" do
    sign_out
    get new_scan_path

    assert_redirected_to new_session_path
  end

  test "shows the reader" do
    get new_scan_path

    assert_response :success
    assert_select "h1", "Read a passport"
  end

  test "a good zone lands on a prefilled document form" do
    post scans_path, params: { mrz: valid_mrz }

    assert_response :redirect
    follow_redirect!

    assert_response :success
    assert_select "input[name='document[expires_on]'][value='2031-02-20']"
    assert_select "option[value='NP'][selected]"
  end

  test "a misread zone explains itself instead of saving a wrong date" do
    post scans_path, params: { mrz: valid_mrz.sub("310220", "310221") }

    assert_response :unprocessable_entity
    assert_select ".errors", /expiry date/
  end

  test "garbage does not blow up" do
    post scans_path, params: { mrz: "hello" }

    assert_response :unprocessable_entity
  end

  # A crafted link must not be able to prefill anything beyond the three fields
  # a scan can legitimately supply.
  test "prefill ignores fields a scan cannot provide" do
    get new_document_path(document: { kind: "passport", issuing_country: "NP",
                                      expires_on: "2031-02-20", notes: "injected", label: "injected" })

    assert_response :success
    assert_select "textarea[name='document[notes]']", text: ""
    assert_select "input[name='document[label]'][value='injected']", count: 0
  end
end
