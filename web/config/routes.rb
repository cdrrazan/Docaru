Rails.application.routes.draw do
  root "pages#home"

  # ---- public: no account, crawlable ---------------------------------------
  #
  # Every playbook is simultaneously a product feature and a page that ranks, so
  # these URLs are readable and stable — "from-gb" rather than a query string,
  # because that is the part of the URL matching what somebody typed into a
  # search box.
  get "when-to-start", to: "calculations#show", as: :calculator

  # Built from the dataset on request. A static file would have to be
  # regenerated every time somebody merges a rule, which is the sort of step
  # that gets skipped until the sitemap describes a site that no longer exists.
  get "sitemap.xml", to: "pages#sitemap", as: :sitemap, defaults: { format: "xml" }

  get "playbooks", to: "playbooks#index", as: :playbooks
  get "playbooks/:country_code/:document_kind/from-:origin",
      to: "playbooks#show", as: :origin_playbook,
      constraints: { country_code: /[a-z]{2}/, origin: /[a-z]{2}/ }
  get "playbooks/:country_code/:document_kind",
      to: "playbooks#show", as: :playbook,
      constraints: { country_code: /[a-z]{2}/ }

  # ---- accounts -------------------------------------------------------------

  resource :plan, only: %i[show update]

  resource :session
  resource :registration, only: %i[new create]
  resources :passwords, param: :token

  # ---- the private plane ----------------------------------------------------

  get "dashboard", to: "dashboard#show", as: :dashboard
  resources :members, except: :show
  # No index: the dashboard is the list, sorted by urgency rather than by name.
  resources :documents, except: :index do
    # Ciphertext in, ciphertext out. The server has no key and no code that
    # would know what to do with one.
    resources :attachments, only: %i[create show destroy]
  end

  # Reading a passport's machine-readable zone instead of typing it.
  resources :scans, only: %i[new create]

  # Installable, because the people this is for check a deadline on a phone
  # abroad rather than at a desk. The service worker caches the public playbooks
  # only — see the rule at the top of that file.
  #
  # The formats are pinned because the templates are manifest.json.erb and
  # service-worker.js, while a request for an extensionless path is html —
  # Rails' own commented-out suggestion raises MissingTemplate as written.
  get "manifest", to: "rails/pwa#manifest", as: :pwa_manifest, defaults: { format: "json" }
  get "service-worker", to: "rails/pwa#service_worker", as: :pwa_service_worker, defaults: { format: "js" }

  get "up" => "rails/health#show", as: :rails_health_check
end
