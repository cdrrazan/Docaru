Rails.application.routes.draw do
  root "pages#home"

  # Public, crawlable, no account required. Every playbook is simultaneously a
  # product feature and a page that ranks, so these URLs are readable and stable
  # — "from-gb" rather than a query string, because that is the part of the URL
  # that matches what somebody typed into a search box.
  get "playbooks", to: "playbooks#index", as: :playbooks
  get "playbooks/:country_code/:document_kind/from-:origin",
      to: "playbooks#show", as: :origin_playbook,
      constraints: { country_code: /[a-z]{2}/, origin: /[a-z]{2}/ }
  get "playbooks/:country_code/:document_kind",
      to: "playbooks#show", as: :playbook,
      constraints: { country_code: /[a-z]{2}/ }

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
