class AllowDocumentsWithoutAnExpiry < ActiveRecord::Migration[8.1]
  # Most of what a household needs to reach from another city never expires at
  # all: a degree certificate, a birth certificate, a marriage certificate, a
  # property deed, a transcript. Requiring an expiry date made every one of them
  # unstorable, which meant the vault could only hold the minority of documents
  # that happen to have deadlines.
  #
  # The deadline is the intelligence layer. It is not the price of admission.
  def change
    change_column_null :documents, :expires_on, true
  end
end
