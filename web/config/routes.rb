Rails.application.routes.draw do
  root "pages#home"

  # ---- public: no account, crawlable ---------------------------------------
  #
  # Every playbook is simultaneously a product feature and a page that ranks, so
  # these URLs are readable and stable — "from-gb" rather than a query string,
  # because that is the part of the URL matching what somebody typed into a
  # search box.
  get "when-to-start", to: "calculations#show", as: :calculator

  get "playbooks", to: "playbooks#index", as: :playbooks
  get "playbooks/:country_code/:document_kind/from-:origin",
      to: "playbooks#show", as: :origin_playbook,
      constraints: { country_code: /[a-z]{2}/, origin: /[a-z]{2}/ }
  get "playbooks/:country_code/:document_kind",
      to: "playbooks#show", as: :playbook,
      constraints: { country_code: /[a-z]{2}/ }

  # ---- accounts -------------------------------------------------------------

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

  get "up" => "rails/health#show", as: :rails_health_check
end
