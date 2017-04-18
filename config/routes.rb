require "sidekiq/web"
require_dependency "scheduler/web"
require_dependency "admin_constraint"
require_dependency "staff_constraint"
require_dependency "homepage_constraint"
require_dependency "permalink_constraint"

# This used to be User#username_format, but that causes a preload of the User object
# and makes Guard not work properly.
USERNAME_ROUTE_FORMAT = /[\w.\-]+?/ unless defined? USERNAME_ROUTE_FORMAT

BACKUP_ROUTE_FORMAT = /.+\.(sql\.gz|tar\.gz|tgz)/i unless defined? BACKUP_ROUTE_FORMAT

Discourse::Application.routes.draw do

  match "/404", to: "exceptions#not_found", via: [:get, :post]
  get "/404-body" => "exceptions#not_found_body"

  post "webhooks/mailgun"  => "webhooks#mailgun"
  post "webhooks/sendgrid" => "webhooks#sendgrid"
  post "webhooks/mailjet"  => "webhooks#mailjet"
  post "webhooks/mandrill" => "webhooks#mandrill"
  post "webhooks/sparkpost" => "webhooks#sparkpost"

  if Rails.env.development?
    mount Sidekiq::Web => "/sidekiq"
    mount Logster::Web => "/logs"
  else
    # only allow sidekiq in master site
    mount Sidekiq::Web => "/sidekiq", constraints: AdminConstraint.new(require_master: true)
    mount Logster::Web => "/logs", constraints: AdminConstraint.new
  end

  resources :about do
    collection do
      get "live_post_counts"
    end
  end

  get "finish-installation" => "finish_installation#index"
  get "finish-installation/register" => "finish_installation#register"
  post "finish-installation/register" => "finish_installation#register"
  get "finish-installation/confirm-email" => "finish_installation#confirm_email"
  put "finish-installation/resend-email" => "finish_installation#resend_email"

  resources :directory_items

  get "site" => "site#site"
  namespace :site do
    get "settings"
    get "custom_html"
    get "banner"
    get "emoji"
  end

  get "site/basic-info" => 'site#basic_info'
  get "site/statistics" => 'site#statistics'

  get "srv/status" => "forums#status"

  get "wizard" => "wizard#index"
  get "wizard/qunit" => "wizard#qunit"
  get 'wizard/steps' => 'steps#index'
  get 'wizard/steps/:id' => "wizard#index"
  put 'wizard/steps/:id' => "steps#update"

  namespace :admin, constraints: StaffConstraint.new do
    get "" => "admin#index"

    get 'plugins' => 'plugins#index'

    resources :site_settings, constraints: AdminConstraint.new do
      collection do
        get "category/:id" => "site_settings#index"
      end
    end

    get "reports/:type" => "reports#show"

    resources :groups, constraints: AdminConstraint.new do
      collection do
        post "refresh_automatic_groups" => "groups#refresh_automatic_groups"
        get 'bulk'
        get 'bulk-complete' => 'groups#bulk'
        put 'bulk' => 'groups#bulk_perform'
      end
      member do
        put "owners" => "groups#add_owners"
        delete "owners" => "groups#remove_owner"
      end
    end

    get "groups/:type" => "groups#show", constraints: AdminConstraint.new
    get "groups/:type/:id" => "groups#show", constraints: AdminConstraint.new

    resources :users, id: USERNAME_ROUTE_FORMAT, except: [:show] do
      collection do
        get "list/:query" => "users#index"
        get "ip-info" => "users#ip_info"
        delete "delete-others-with-same-ip" => "users#delete_other_accounts_with_same_ip"
        get "total-others-with-same-ip" => "users#total_other_accounts_with_same_ip"
        put "approve-bulk" => "users#approve_bulk"
        delete "reject-bulk" => "users#reject_bulk"
      end
      put "suspend"
      put "delete_all_posts"
      put "unsuspend"
      put "revoke_admin", constraints: AdminConstraint.new
      put "grant_admin", constraints: AdminConstraint.new
      post "generate_api_key", constraints: AdminConstraint.new
      delete "revoke_api_key", constraints: AdminConstraint.new
      put "revoke_moderation", constraints: AdminConstraint.new
      put "grant_moderation", constraints: AdminConstraint.new
      put "approve"
      post "refresh_browsers", constraints: AdminConstraint.new
      post "log_out", constraints: AdminConstraint.new
      put "activate"
      put "deactivate"
      put "block"
      put "unblock"
      put "trust_level"
      put "trust_level_lock"
      put "primary_group"
      post "groups" => "users#add_group", constraints: AdminConstraint.new
      delete "groups/:group_id" => "users#remove_group", constraints: AdminConstraint.new
      get "badges"
      get "leader_requirements" => "users#tl3_requirements"
      get "tl3_requirements"
      put "anonymize"
      post "reset_bounce_score"
    end
    get "users/:id.json" => 'users#show', defaults: {format: 'json'}
    get 'users/:id/:username' => 'users#show', constraints: {username: USERNAME_ROUTE_FORMAT}
    get 'users/:id/:username/badges' => 'users#show'
    get 'users/:id/:username/tl3_requirements' => 'users#show'


    post "users/sync_sso" => "users#sync_sso", constraints: AdminConstraint.new
    post "users/invite_admin" => "users#invite_admin", constraints: AdminConstraint.new

    resources :impersonate, constraints: AdminConstraint.new

    resources :email, constraints: AdminConstraint.new do
      collection do
        post "test"
        get "sent"
        get "skipped"
        get "bounced"
        get "received"
        get "rejected"
        get "/incoming/:id/raw" => "email#raw_email"
        get "/incoming/:id" => "email#incoming"
        get "/incoming_from_bounced/:id" => "email#incoming_from_bounced"
        get "preview-digest" => "email#preview_digest"
        get "send-digest" => "email#send_digest"
        get "smtp_should_reject"
        post "handle_mail"
      end
    end

    scope "/logs" do
      resources :staff_action_logs,     only: [:index]
      get 'staff_action_logs/:id/diff' => 'staff_action_logs#diff'
      resources :screened_emails,       only: [:index, :destroy]
      resources :screened_ip_addresses, only: [:index, :create, :update, :destroy] do
        collection do
          post "roll_up"
        end
      end
      resources :screened_urls,         only: [:index]
    end

    get "/logs" => "staff_action_logs#index"

    get "customize" => "color_schemes#index", constraints: AdminConstraint.new
    get "customize/themes" => "themes#index", constraints: AdminConstraint.new
    get "customize/colors" => "color_schemes#index", constraints: AdminConstraint.new
    get "customize/colors/:id" => "color_schemes#index", constraints: AdminConstraint.new
    get "customize/permalinks" => "permalinks#index", constraints: AdminConstraint.new
    get "customize/embedding" => "embedding#show", constraints: AdminConstraint.new
    put "customize/embedding" => "embedding#update", constraints: AdminConstraint.new

    get "flags" => "flags#index"
    get "flags/:filter" => "flags#index"
    post "flags/agree/:id" => "flags#agree"
    post "flags/disagree/:id" => "flags#disagree"
    post "flags/defer/:id" => "flags#defer"

    resources :themes, constraints: AdminConstraint.new
    post "themes/import" => "themes#import"
    get "themes/:id/preview" => "themes#preview"

    scope "/customize", constraints: AdminConstraint.new do
      resources :user_fields, constraints: AdminConstraint.new
      resources :emojis, constraints: AdminConstraint.new

      get 'themes/:id/:target/:field_name/edit' => 'themes#index'
      get 'themes/:id' => 'themes#index'

      # They have periods in their URLs often:
      get 'site_texts'          => 'site_texts#index'
      get 'site_texts/(:id)'    => 'site_texts#show',   constraints: { id: /[\w.\-]+/i }
      put 'site_texts/(:id)'    => 'site_texts#update', constraints: { id: /[\w.\-]+/i }
      delete 'site_texts/(:id)' => 'site_texts#revert', constraints: { id: /[\w.\-]+/i }

      get 'email_templates'          => 'email_templates#index'
      get 'email_templates/(:id)'    => 'email_templates#show',   constraints: { id: /[0-9a-z_.]+/ }
      put 'email_templates/(:id)'    => 'email_templates#update', constraints: { id: /[0-9a-z_.]+/ }
      delete 'email_templates/(:id)' => 'email_templates#revert', constraints: { id: /[0-9a-z_.]+/ }
    end

    resources :embeddable_hosts, constraints: AdminConstraint.new
    resources :color_schemes, constraints: AdminConstraint.new

    resources :permalinks, constraints: AdminConstraint.new

    get "version_check" => "versions#show"

    resources :dashboard, only: [:index] do
      collection do
        get "problems"
      end
    end

    resources :api, only: [:index], constraints: AdminConstraint.new do
      collection do
        get "keys" => "api#index"
        post "key" => "api#create_master_key"
        put "key" => "api#regenerate_key"
        delete "key" => "api#revoke_key"

        resources :web_hooks
        get 'web_hook_events/:id' => 'web_hooks#list_events', as: :web_hook_events
        get 'web_hooks/:id/events' => 'web_hooks#list_events'
        get 'web_hooks/:id/events/bulk' => 'web_hooks#bulk_events'
        post 'web_hooks/:web_hook_id/events/:event_id/redeliver' => 'web_hooks#redeliver_event'
        post 'web_hooks/:id/ping' => 'web_hooks#ping'
      end
    end

    resources :backups, only: [:index, :create], constraints: AdminConstraint.new do
      member do
        get "" => "backups#show", constraints: { id: BACKUP_ROUTE_FORMAT }
        put "" => "backups#email", constraints: { id: BACKUP_ROUTE_FORMAT }
        delete "" => "backups#destroy", constraints: { id: BACKUP_ROUTE_FORMAT }
        post "restore" => "backups#restore", constraints: { id: BACKUP_ROUTE_FORMAT }
      end
      collection do
        get "logs" => "backups#logs"
        get "status" => "backups#status"
        delete "cancel" => "backups#cancel"
        post "rollback" => "backups#rollback"
        put "readonly" => "backups#readonly"
        get "upload" => "backups#check_backup_chunk"
        post "upload" => "backups#upload_backup_chunk"
      end
    end

    resources :badges, constraints: AdminConstraint.new do
      collection do
        get "types" => "badges#badge_types"
        post "badge_groupings" => "badges#save_badge_groupings"
        post "preview" => "badges#preview"
      end
    end

    get "memory_stats"=> "diagnostics#memory_stats", constraints: AdminConstraint.new
    get "dump_heap"=> "diagnostics#dump_heap", constraints: AdminConstraint.new
    get "dump_statement_cache"=> "diagnostics#dump_statement_cache", constraints: AdminConstraint.new

  end # admin namespace

  get "email_preferences" => "email#preferences_redirect", :as => "email_preferences_redirect"

  get "email/unsubscribe/:key" => "email#unsubscribe", as: "email_unsubscribe"
  get "email/unsubscribed" => "email#unsubscribed", as: "email_unsubscribed"
  post "email/unsubscribe/:key" => "email#perform_unsubscribe", as: "email_perform_unsubscribe"

  get "extra-locales/:bundle" => "extra_locales#show"

  resources :session, id: USERNAME_ROUTE_FORMAT, only: [:create, :destroy, :become] do
    get 'become'
    collection do
      post "forgot_password"
    end
  end

  get "session/sso" => "session#sso"
  get "session/sso_login" => "session#sso_login"
  get "session/sso_provider" => "session#sso_provider"
  get "session/current" => "session#current"
  get "session/csrf" => "session#csrf"
  get "composer_messages" => "composer_messages#index"

  resources :static
  post "login" => "static#enter", constraints: { format: /(json|html)/ }
  get "login" => "static#show", id: "login", constraints: { format: /(json|html)/ }
  get "password-reset" => "static#show", id: "password_reset", constraints: { format: /(json|html)/ }
  get "faq" => "static#show", id: "faq", constraints: { format: /(json|html)/ }
  get "guidelines" => "static#show", id: "guidelines", as: 'guidelines', constraints: { format: /(json|html)/ }
  get "tos" => "static#show", id: "tos", as: 'tos', constraints: { format: /(json|html)/ }
  get "privacy" => "static#show", id: "privacy", as: 'privacy', constraints: { format: /(json|html)/ }
  get "signup" => "static#show", id: "signup", constraints: { format: /(json|html)/ }
  get "login-preferences" => "static#show", id: "login", constraints: { format: /(json|html)/ }

  get "my/*path", to: 'users#my_redirect'
  get "user_preferences" => "users#user_preferences_redirect"

  %w{users u}.each_with_index do |root_path, index|
    resources :users, except: [:show, :update, :destroy], path: root_path do
      collection do
        get "check_username"
        get "is_local_username"
      end
    end

    put "#{root_path}/update-activation-email" => "users#update_activation_email"
    get "#{root_path}/hp" => "users#get_honeypot_value"
    get "#{root_path}/admin-login" => "users#admin_login"
    put "#{root_path}/admin-login" => "users#admin_login"
    get "#{root_path}/admin-login/:token" => "users#admin_login"
    post "#{root_path}/toggle-anon" => "users#toggle_anon"
    post "#{root_path}/read-faq" => "users#read_faq"
    get "#{root_path}/search/users" => "users#search_users"
    get "#{root_path}/account-created/" => "users#account_created"
    get({ "#{root_path}/password-reset/:token" => "users#password_reset" }.merge(index == 1 ? { as: :password_reset_token } : {}))
    get "#{root_path}/confirm-email-token/:token" => "users#confirm_email_token", constraints: { format: 'json' }
    put "#{root_path}/password-reset/:token" => "users#password_reset"
    get "#{root_path}/activate-account/:token" => "users#activate_account"
    put({ "#{root_path}/activate-account/:token" => "users#perform_account_activation" }.merge(index == 1 ? { as: 'perform_activate_account' } : {}))
    get "#{root_path}/authorize-email/:token" => "users_email#confirm"
    get({
      "#{root_path}/confirm-admin/:token" => "users#confirm_admin",
      constraints: { token: /[0-9a-f]+/ }
    }.merge(index == 1 ? { as: 'confirm_admin' } : {}))
    post "#{root_path}/confirm-admin/:token" => "users#confirm_admin", constraints: { token: /[0-9a-f]+/ }
    get "#{root_path}/:username/private-messages" => "user_actions#private_messages", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/private-messages/:filter" => "user_actions#private_messages", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/messages" => "user_actions#private_messages", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/messages/:filter" => "user_actions#private_messages", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/messages/group/:group_name" => "user_actions#private_messages", constraints: {username: USERNAME_ROUTE_FORMAT, group_name: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/messages/group/:group_name/archive" => "user_actions#private_messages", constraints: {username: USERNAME_ROUTE_FORMAT, group_name: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username.json" => "users#show", constraints: {username: USERNAME_ROUTE_FORMAT}, defaults: {format: :json}
    get({ "#{root_path}/:username" => "users#show", constraints: { username: USERNAME_ROUTE_FORMAT, format: /(json|html)/ } }.merge(index == 1 ? { as: 'user' } : {}))
    put "#{root_path}/:username" => "users#update", constraints: {username: USERNAME_ROUTE_FORMAT}, defaults: { format: :json }
    get "#{root_path}/:username/emails" => "users#check_emails", constraints: {username: USERNAME_ROUTE_FORMAT}
    get({ "#{root_path}/:username/preferences" => "users#preferences", constraints: { username: USERNAME_ROUTE_FORMAT } }.merge(index == 1 ? { as: :email_preferences } : {}))
    get "#{root_path}/:username/preferences/email" => "users_email#index", constraints: {username: USERNAME_ROUTE_FORMAT}
    put "#{root_path}/:username/preferences/email" => "users_email#update", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/preferences/about-me" => "users#preferences", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/preferences/badge_title" => "users#preferences", constraints: {username: USERNAME_ROUTE_FORMAT}
    put "#{root_path}/:username/preferences/badge_title" => "users#badge_title", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/preferences/username" => "users#preferences", constraints: {username: USERNAME_ROUTE_FORMAT}
    put "#{root_path}/:username/preferences/username" => "users#username", constraints: {username: USERNAME_ROUTE_FORMAT}
    delete "#{root_path}/:username/preferences/user_image" => "users#destroy_user_image", constraints: {username: USERNAME_ROUTE_FORMAT}
    put "#{root_path}/:username/preferences/avatar/pick" => "users#pick_avatar", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/preferences/card-badge" => "users#card_badge", constraints: {username: USERNAME_ROUTE_FORMAT}
    put "#{root_path}/:username/preferences/card-badge" => "users#update_card_badge", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/staff-info" => "users#staff_info", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/summary" => "users#summary", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/invited" => "users#invited", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/invited_count" => "users#invited_count", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/invited/:filter" => "users#invited", constraints: {username: USERNAME_ROUTE_FORMAT}
    post "#{root_path}/action/send_activation_email" => "users#send_activation_email"
    get "#{root_path}/:username/summary" => "users#show", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/activity/topics.rss" => "list#user_topics_feed", format: :rss, constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/activity.rss" => "posts#user_posts_feed", format: :rss, constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/activity" => "users#show", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/activity/:filter" => "users#show", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/badges" => "users#show", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/notifications" => "users#show", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/notifications/:filter" => "users#show", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/activity/pending" => "users#show", constraints: {username: USERNAME_ROUTE_FORMAT}
    delete "#{root_path}/:username" => "users#destroy", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/by-external/:external_id" => "users#show", constraints: {external_id: /[^\/]+/}
    get "#{root_path}/:username/flagged-posts" => "users#show", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/deleted-posts" => "users#show", constraints: {username: USERNAME_ROUTE_FORMAT}
    get "#{root_path}/:username/topic-tracking-state" => "users#topic_tracking_state", constraints: {username: USERNAME_ROUTE_FORMAT}
  end

  get "user-badges/:username.json" => "user_badges#username", constraints: {username: USERNAME_ROUTE_FORMAT}, defaults: {format: :json}
  get "user-badges/:username" => "user_badges#username", constraints: {username: USERNAME_ROUTE_FORMAT}

  post "user_avatar/:username/refresh_gravatar" => "user_avatars#refresh_gravatar", constraints: {username: USERNAME_ROUTE_FORMAT}
  get "letter_avatar/:username/:size/:version.png" => "user_avatars#show_letter", format: false, constraints: { hostname: /[\w\.-]+/, size: /\d+/, username: USERNAME_ROUTE_FORMAT}
  get "user_avatar/:hostname/:username/:size/:version.png" => "user_avatars#show", format: false, constraints: { hostname: /[\w\.-]+/, size: /\d+/, username: USERNAME_ROUTE_FORMAT }

  # in most production settings this is bypassed
  get "letter_avatar_proxy/:version/letter/:letter/:color/:size.png" => "user_avatars#show_proxy_letter"

  get "highlight-js/:hostname/:version.js" => "highlight_js#show", format: false, constraints: { hostname: /[\w\.-]+/ }

  get "stylesheets/:name.css.map" => "stylesheets#show_source_map", constraints: { name: /[-a-z0-9_]+/ }
  get "stylesheets/:name.css" => "stylesheets#show", constraints: { name: /[-a-z0-9_]+/ }

  post "uploads" => "uploads#create"

  # used to download original images
  get "uploads/:site/:sha(.:extension)" => "uploads#show", constraints: { site: /\w+/, sha: /\h{40}/, extension: /[a-z0-9\.]+/i }
  # used to download attachments
  get "uploads/:site/original/:tree:sha(.:extension)" => "uploads#show", constraints: { site: /\w+/, tree: /([a-z0-9]+\/)+/i, sha: /\h{40}/, extension: /[a-z0-9\.]+/i }
  # used to download attachments (old route)
  get "uploads/:site/:id/:sha" => "uploads#show", constraints: { site: /\w+/, id: /\d+/, sha: /\h{16}/ }

  get "posts" => "posts#latest", id: "latest_posts"
  get "private-posts" => "posts#latest", id: "private_posts"
  get "posts/by_number/:topic_id/:post_number" => "posts#by_number"
  get "posts/:id/reply-history" => "posts#reply_history"
  get "posts/:username/deleted" => "posts#deleted_posts", constraints: {username: USERNAME_ROUTE_FORMAT}
  get "posts/:username/flagged" => "posts#flagged_posts", constraints: {username: USERNAME_ROUTE_FORMAT}

  resources :groups, id: USERNAME_ROUTE_FORMAT do
    get "posts.rss" => "groups#posts_feed", format: :rss
    get "mentions.rss" => "groups#mentions_feed", format: :rss

    get 'activity' => "groups#show"
    get 'activity/:filter' => "groups#show"
    get 'members'
    get 'owners'
    get 'posts'
    get 'topics'
    get 'mentions'
    get 'messages'
    get 'counts'
    get 'mentionable'
    get 'logs' => 'groups#histories'

    member do
      put "members" => "groups#add_members"
      delete "members" => "groups#remove_member"
      post "notifications" => "groups#set_notifications"
    end
  end

  # aliases so old API code works
  delete "admin/groups/:id/members" => "groups#remove_member", constraints: AdminConstraint.new
  put "admin/groups/:id/members" => "groups#add_members", constraints: AdminConstraint.new

  resources :posts do
    put "bookmark"
    put "wiki"
    put "post_type"
    put "rebake"
    put "unhide"
    get "replies"
    get "revisions/latest" => "posts#latest_revision"
    get "revisions/:revision" => "posts#revisions", constraints: { revision: /\d+/ }
    put "revisions/:revision/hide" => "posts#hide_revision", constraints: { revision: /\d+/ }
    put "revisions/:revision/show" => "posts#show_revision", constraints: { revision: /\d+/ }
    put "revisions/:revision/revert" => "posts#revert", constraints: { revision: /\d+/ }
    put "recover"
    collection do
      delete "destroy_many"
      put "merge_posts"
    end
  end

  get 'notifications' => 'notifications#index'
  put 'notifications/mark-read' => 'notifications#mark_read'
  # creating an alias cause the api was extended to mark a single notification
  # this allows us to cleanly target it
  put 'notifications/read' => 'notifications#mark_read'

  match "/auth/:provider/callback", to: "users/omniauth_callbacks#complete", via: [:get, :post]
  match "/auth/failure", to: "users/omniauth_callbacks#failure", via: [:get, :post]

  resources :clicks do
    collection do
      get "track"
    end
  end

  get "excerpt" => "excerpt#show"

  resources :post_action_users
  resources :post_actions do
    collection do
      get "users"
      post "defer_flags"
    end
  end
  resources :user_actions

  resources :badges, only: [:index]
  get "/badges/:id(/:slug)" => "badges#show"
  resources :user_badges, only: [:index, :create, :destroy]


  get '/c', to: redirect('/categories')

  resources :categories, :except => :show
  post "category/:category_id/move" => "categories#move"
  post "categories/reorder" => "categories#reorder"
  post "category/:category_id/notifications" => "categories#set_notifications"
  put "category/:category_id/slug" => "categories#update_slug"

  get "categories_and_latest" => "categories#categories_and_latest"

  get "c/:id/show" => "categories#show"
  get "c/:category_slug/find_by_slug" => "categories#find_by_slug"
  get "c/:parent_category_slug/:category_slug/find_by_slug" => "categories#find_by_slug"
  get "c/:category.rss" => "list#category_feed", format: :rss
  get "c/:parent_category/:category.rss" => "list#category_feed", format: :rss
  get "c/:category" => "list#category_default", as: "category_default"
  get "c/:category/none" => "list#category_none_latest"
  get "c/:parent_category/:category/(:id)" => "list#parent_category_category_latest", constraints: { id: /\d+/ }
  get "c/:category/l/top" => "list#category_top", as: "category_top"
  get "c/:category/none/l/top" => "list#category_none_top", as: "category_none_top"
  get "c/:parent_category/:category/l/top" => "list#parent_category_category_top", as: "parent_category_category_top"

  get "category_hashtags/check" => "category_hashtags#check"

  TopTopic.periods.each do |period|
    get "top/#{period}.rss" => "list#top_#{period}_feed", format: :rss
    get "top/#{period}" => "list#top_#{period}"
    get "c/:category/l/top/#{period}" => "list#category_top_#{period}", as: "category_top_#{period}"
    get "c/:category/none/l/top/#{period}" => "list#category_none_top_#{period}", as: "category_none_top_#{period}"
    get "c/:parent_category/:category/l/top/#{period}" => "list#parent_category_category_top_#{period}", as: "parent_category_category_top_#{period}"
  end

  Discourse.anonymous_filters.each do |filter|
    get "#{filter}.rss" => "list##{filter}_feed", format: :rss
  end

  Discourse.filters.each do |filter|
    get "#{filter}" => "list##{filter}", constraints: { format: /(json|html)/ }
    get "c/:category/l/#{filter}" => "list#category_#{filter}", as: "category_#{filter}"
    get "c/:category/none/l/#{filter}" => "list#category_none_#{filter}", as: "category_none_#{filter}"
    get "c/:parent_category/:category/l/#{filter}" => "list#parent_category_category_#{filter}", as: "parent_category_category_#{filter}"
  end

  get "category/*path" => "categories#redirect"

  get "top" => "list#top"
  get "search/query" => "search#query"
  get "search" => "search#show"

  # Topics resource
  get "t/:id" => "topics#show"
  put "t/:id" => "topics#update"
  delete "t/:id" => "topics#destroy"
  put "t/:id/archive-message" => "topics#archive_message"
  put "t/:id/move-to-inbox" => "topics#move_to_inbox"
  put "t/:id/convert-topic/:type" => "topics#convert_topic"
  put "topics/bulk"
  put "topics/reset-new" => 'topics#reset_new'
  post "topics/timings"

  get 'topics/similar_to' => 'similar_topics#index'
  resources :similar_topics

  get "topics/feature_stats"
  get "topics/created-by/:username" => "list#topics_by", as: "topics_by", constraints: {username: USERNAME_ROUTE_FORMAT}
  get "topics/private-messages/:username" => "list#private_messages", as: "topics_private_messages", constraints: {username: USERNAME_ROUTE_FORMAT}
  get "topics/private-messages-sent/:username" => "list#private_messages_sent", as: "topics_private_messages_sent", constraints: {username: USERNAME_ROUTE_FORMAT}
  get "topics/private-messages-archive/:username" => "list#private_messages_archive", as: "topics_private_messages_archive", constraints: {username: USERNAME_ROUTE_FORMAT}
  get "topics/private-messages-unread/:username" => "list#private_messages_unread", as: "topics_private_messages_unread", constraints: {username: USERNAME_ROUTE_FORMAT}
  get "topics/private-messages-group/:username/:group_name.json" => "list#private_messages_group", as: "topics_private_messages_group", constraints: {
    username: USERNAME_ROUTE_FORMAT,
    group_name: USERNAME_ROUTE_FORMAT
  }

  get "topics/private-messages-group/:username/:group_name/archive.json" => "list#private_messages_group_archive", as: "topics_private_messages_group_archive", constraints: {
    username: USERNAME_ROUTE_FORMAT,
    group_name: USERNAME_ROUTE_FORMAT
  }

  get 'embed/comments' => 'embed#comments'
  get 'embed/count' => 'embed#count'
  get 'embed/info' => 'embed#info'

  get "new-topic" => "list#latest"
  get "new-message" => "list#latest"

  # Topic routes
  get "t/id_for/:slug" => "topics#id_for_slug"
  get "t/:slug/:topic_id/print" => "topics#show", format: :html, print: true, constraints: {topic_id: /\d+/}
  get "t/:slug/:topic_id/wordpress" => "topics#wordpress", constraints: {topic_id: /\d+/}
  get "t/:topic_id/wordpress" => "topics#wordpress", constraints: {topic_id: /\d+/}
  get "t/:slug/:topic_id/moderator-liked" => "topics#moderator_liked", constraints: {topic_id: /\d+/}
  get "t/:slug/:topic_id/summary" => "topics#show", defaults: {summary: true}, constraints: {topic_id: /\d+/}
  get "t/:slug/:topic_id/unsubscribe" => "topics#unsubscribe", constraints: {topic_id: /\d+/}
  get "t/:topic_id/unsubscribe" => "topics#unsubscribe", constraints: {topic_id: /\d+/}
  get "t/:topic_id/summary" => "topics#show", constraints: {topic_id: /\d+/}
  put "t/:slug/:topic_id" => "topics#update", constraints: {topic_id: /\d+/}
  put "t/:slug/:topic_id/star" => "topics#star", constraints: {topic_id: /\d+/}
  put "t/:topic_id/star" => "topics#star", constraints: {topic_id: /\d+/}
  put "t/:slug/:topic_id/status" => "topics#status", constraints: {topic_id: /\d+/}
  put "t/:topic_id/status" => "topics#status", constraints: {topic_id: /\d+/}
  put "t/:topic_id/clear-pin" => "topics#clear_pin", constraints: {topic_id: /\d+/}
  put "t/:topic_id/re-pin" => "topics#re_pin", constraints: {topic_id: /\d+/}
  put "t/:topic_id/mute" => "topics#mute", constraints: {topic_id: /\d+/}
  put "t/:topic_id/unmute" => "topics#unmute", constraints: {topic_id: /\d+/}
  post "t/:topic_id/status_update" => "topics#status_update", constraints: {topic_id: /\d+/}
  put "t/:topic_id/make-banner" => "topics#make_banner", constraints: {topic_id: /\d+/}
  put "t/:topic_id/remove-banner" => "topics#remove_banner", constraints: {topic_id: /\d+/}
  put "t/:topic_id/remove-allowed-user" => "topics#remove_allowed_user", constraints: {topic_id: /\d+/}
  put "t/:topic_id/remove-allowed-group" => "topics#remove_allowed_group", constraints: {topic_id: /\d+/}
  put "t/:topic_id/recover" => "topics#recover", constraints: {topic_id: /\d+/}
  get "t/:topic_id/:post_number" => "topics#show", constraints: {topic_id: /\d+/, post_number: /\d+/}
  get "t/:topic_id/last" => "topics#show", post_number: 99999999, constraints: {topic_id: /\d+/}
  get "t/:slug/:topic_id.rss" => "topics#feed", format: :rss, constraints: {topic_id: /\d+/}
  get "t/:slug/:topic_id" => "topics#show", constraints: {topic_id: /\d+/}
  get "t/:slug/:topic_id/:post_number" => "topics#show", constraints: {topic_id: /\d+/, post_number: /\d+/}
  get "t/:slug/:topic_id/last" => "topics#show", post_number: 99999999, constraints: {topic_id: /\d+/}
  get "t/:topic_id/posts" => "topics#posts", constraints: {topic_id: /\d+/}, format: :json
  get "t/:topic_id/excerpts" => "topics#excerpts", constraints: {topic_id: /\d+/}, format: :json
  post "t/:topic_id/timings" => "topics#timings", constraints: {topic_id: /\d+/}
  post "t/:topic_id/invite" => "topics#invite", constraints: {topic_id: /\d+/}
  post "t/:topic_id/invite-group" => "topics#invite_group", constraints: {topic_id: /\d+/}
  post "t/:topic_id/move-posts" => "topics#move_posts", constraints: {topic_id: /\d+/}
  post "t/:topic_id/merge-topic" => "topics#merge_topic", constraints: {topic_id: /\d+/}
  post "t/:topic_id/change-owner" => "topics#change_post_owners", constraints: {topic_id: /\d+/}
  put "t/:topic_id/change-timestamp" => "topics#change_timestamps", constraints: {topic_id: /\d+/}
  delete "t/:topic_id/timings" => "topics#destroy_timings", constraints: {topic_id: /\d+/}
  put "t/:topic_id/bookmark" => "topics#bookmark", constraints: {topic_id: /\d+/}
  put "t/:topic_id/remove_bookmarks" => "topics#remove_bookmarks", constraints: {topic_id: /\d+/}

  post "t/:topic_id/notifications" => "topics#set_notifications" , constraints: {topic_id: /\d+/}

  get "p/:post_id(/:user_id)" => "posts#short_link"
  get "/posts/:id/cooked" => "posts#cooked"
  get "/posts/:id/expand-embed" => "posts#expand_embed"
  get "/posts/:id/raw" => "posts#markdown_id"
  get "/posts/:id/raw-email" => "posts#raw_email"
  get "raw/:topic_id(/:post_number)" => "posts#markdown_num"

  resources :queued_posts, constraints: StaffConstraint.new
  get 'queued-posts' => 'queued_posts#index'

  resources :invites
  post "invites/upload_csv" => "invites#upload_csv"
  post "invites/reinvite" => "invites#resend_invite"
  post "invites/reinvite-all" => "invites#resend_all_invites"
  post "invites/link" => "invites#create_invite_link"
  post "invites/disposable" => "invites#create_disposable_invite"
  get "invites/redeem/:token" => "invites#redeem_disposable_invite"
  delete "invites" => "invites#destroy"
  put "invites/show/:id" => "invites#perform_accept_invitation", as: 'perform_accept_invite'

  resources :export_csv do
    collection do
      post "export_entity" => "export_csv#export_entity"
    end
    member do
      get "" => "export_csv#show", constraints: { id: /[^\/]+/ }
    end
  end

  get "onebox" => "onebox#show"

  get "exception" => "list#latest"

  get "message-bus/poll" => "message_bus#poll"

  get "draft" => "draft#show"
  post "draft" => "draft#update"
  delete "draft" => "draft#destroy"

  get "cdn_asset/:site/*path" => "static#cdn_asset", format: false
  get "brotli_asset/*path" => "static#brotli_asset", format: false

  get "favicon/proxied" => "static#favicon", format: false

  get "robots.txt" => "robots_txt#index"
  get "manifest.json" => "metadata#manifest", as: :manifest
  get "opensearch" => "metadata#opensearch", format: :xml

  scope "/tags" do
    get '/' => 'tags#index'
    get '/filter/list' => 'tags#index'
    get '/filter/search' => 'tags#search'
    get '/check' => 'tags#check_hashtag'
    constraints(tag_id: /[^\/]+?/, format: /json|rss/) do
      get '/:tag_id.rss' => 'tags#tag_feed'
      get '/:tag_id' => 'tags#show', as: 'tag_show'
      get '/c/:category/:tag_id' => 'tags#show', as: 'tag_category_show'
      get '/c/:parent_category/:category/:tag_id' => 'tags#show', as: 'tag_parent_category_category_show'
      get '/intersection/:tag_id/*additional_tag_ids' => 'tags#show', as: 'tag_intersection'
      get '/:tag_id/notifications' => 'tags#notifications'
      put '/:tag_id/notifications' => 'tags#update_notifications'
      put '/:tag_id' => 'tags#update'
      delete '/:tag_id' => 'tags#destroy'

      Discourse.filters.each do |filter|
        get "/:tag_id/l/#{filter}" => "tags#show_#{filter}", as: "tag_show_#{filter}"
        get "/c/:category/:tag_id/l/#{filter}" => "tags#show_#{filter}", as: "tag_category_show_#{filter}"
        get "/c/:parent_category/:category/:tag_id/l/#{filter}" => "tags#show_#{filter}", as: "tag_parent_category_category_show_#{filter}"
      end
    end
  end

  resources :tag_groups, except: [:new, :edit] do
    collection do
      get '/filter/search' => 'tag_groups#search'
    end
  end

  Discourse.filters.each do |filter|
    root to: "list##{filter}", constraints: HomePageConstraint.new("#{filter}"), :as => "list_#{filter}"
  end
  # special case for categories
  root to: "categories#index", constraints: HomePageConstraint.new("categories"), :as => "categories_index"
  # special case for top
  root to: "list#top", constraints: HomePageConstraint.new("top"), :as => "top_lists"

  root to: 'finish_installation#index', constraints: HomePageConstraint.new("finish_installation"), as: 'installation_redirect'

  get "/user-api-key/new" => "user_api_keys#new"
  post "/user-api-key" => "user_api_keys#create"
  post "/user-api-key/revoke" => "user_api_keys#revoke"
  post "/user-api-key/undo-revoke" => "user_api_keys#undo_revoke"

  get "/safe-mode" => "safe_mode#index"
  post "/safe-mode" => "safe_mode#enter", as: "safe_mode_enter"

  get "/themes/assets/:key" => "themes#assets"

  get "*url", to: 'permalinks#show', constraints: PermalinkConstraint.new

end
