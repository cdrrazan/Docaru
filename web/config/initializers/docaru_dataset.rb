# frozen_string_literal: true

# The rules dataset is plain Ruby living outside the Rails tree, in the
# repository root, because it is the public artefact — contributors correcting a
# renewal date should never have to know this application exists. It is required
# explicitly rather than autoloaded for exactly that reason: it does not belong
# to Rails, and Rails does not own its reloading.
require Rails.root.join("..", "lib", "docaru", "dataset").to_s
