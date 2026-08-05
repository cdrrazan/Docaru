class DropRedundantDocumentIndexes < ActiveRecord::Migration[8.1]
  # `t.references :document` adds an index on document_id, and both tables then
  # add a composite starting with the same column. MySQL uses the leftmost
  # prefix of the composite for every lookup the single-column index could
  # serve, so the extra index is never read — it is only maintained, on the two
  # tables written most often: one row per uploaded page, and one per reminder
  # sent by the nightly sweep.
  #
  # The foreign key stays valid throughout. MySQL requires an index on the
  # referencing column and accepts a composite whose leftmost column is that
  # one, which is exactly what remains.

  def up
    remove_index :attachments, :document_id, name: "index_attachments_on_document_id"
    remove_index :reminders, :document_id, name: "index_reminders_on_document_id"
  end

  def down
    add_index :attachments, :document_id, name: "index_attachments_on_document_id"
    add_index :reminders, :document_id, name: "index_reminders_on_document_id"
  end
end
