# frozen_string_literal: true

module ApplicationHelper
  # Where this page really lives.
  #
  # Defaults to the current URL with the query string dropped, which is the
  # right answer for every page here: no parameter this application accepts
  # changes what a page *is*, and several of them (the calculator's) are
  # deliberately unbounded. A page that needs a different canonical sets
  # content_for(:canonical).
  def canonical_url
    content_for(:canonical).presence || url_for(only_path: false, params: {})
  end

  # Playbook links are meant to be pasted into forum threads and family chats —
  # that is the distribution channel, not an afterthought — and a link with no
  # card renders as a bare URL nobody clicks.
  #
  # Squished because these are written as wrapped multi-line ERB blocks, and the
  # newlines survive into the attribute otherwise, which truncates the card at
  # the first line break.
  def social_title = meta_text(content_for(:title), "Renewal playbooks")

  def social_description
    meta_text(content_for(:description),
              "Every document you own has a deadline. We tell you which one is next, " \
              "and exactly what to do about it.")
  end

  private

  def meta_text(value, fallback) = value.presence&.to_s&.squish.presence || fallback
end
