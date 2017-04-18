require File.expand_path('../boot', __FILE__)
require 'rails/all'

# Plugin related stuff
require_relative '../lib/discourse_event'
require_relative '../lib/discourse_plugin'
require_relative '../lib/discourse_plugin_registry'

require_relative '../lib/plugin_gem'

# Global config
require_relative '../app/models/global_setting'
GlobalSetting.configure!
unless Rails.env.test? && ENV['LOAD_PLUGINS'] != "1"
  require_relative '../lib/custom_setting_providers'
end
GlobalSetting.load_defaults

require 'pry-rails' if Rails.env.development?

if defined?(Bundler)
  Bundler.require(*Rails.groups(assets: %w(development test profile)))
end


module Discourse
  class Application < Rails::Application

    def config.database_configuration
      if Rails.env.production?
        GlobalSetting.database_config
      else
        super
      end
    end
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    require 'discourse'
    require 'es6_module_transpiler/rails'
    require 'js_locale_helper'

    # tiny file needed by site settings
    require 'highlight_js/highlight_js'

    # mocha hates us, active_support/testing/mochaing.rb line 2 is requiring the wrong
    #  require, patched in source, on upgrade remove this
    if Rails.env.test? || Rails.env.development?
      require "mocha/version"
      require "mocha/deprecation"
      if Mocha::VERSION == "0.13.3" && Rails::VERSION::STRING == "3.2.12"
        Mocha::Deprecation.mode = :disabled
      end
    end

    # Disable so this is only run manually
    # we may want to change this later on
    # issue is image_optim crashes on missing dependencies
    config.assets.image_optim = false

    # Custom directories with classes and modules you want to be autoloadable.
    config.autoload_paths += Dir["#{config.root}/app/serializers"]
    config.autoload_paths += Dir["#{config.root}/lib/validators/"]
    config.autoload_paths += Dir["#{config.root}/app"]

    # Only load the plugins named here, in the order given (default is alphabetical).
    # :all can be used as a placeholder for all plugins not explicitly named.
    # config.plugins = [ :exception_notification, :ssl_requirement, :all ]

    config.assets.paths += %W(#{config.root}/config/locales #{config.root}/public/javascripts)

    # Allows us to skip minifincation on some files
    config.assets.skip_minification = []

    # explicitly precompile any images in plugins ( /assets/images ) path
    config.assets.precompile += [lambda do |filename, path|
      path =~ /assets\/images/ && !%w(.js .css).include?(File.extname(filename))
    end]

    config.assets.precompile += %w{
                                 vendor.js admin.js preload-store.js
                                 browser-update.js break_string.js ember_jquery.js
                                 pretty-text-bundle.js wizard-application.js
                                 wizard-vendor.js plugin.js plugin-third-party.js
                                 }

    # Precompile all available locales
    Dir.glob("#{config.root}/app/assets/javascripts/locales/*.js.erb").each do |file|
      config.assets.precompile << "locales/#{file.match(/([a-z_A-Z]+\.js)\.erb$/)[1]}"
    end

    # out of the box sprockets 3 grabs loose files that are hanging in assets,
    # the exclusion list does not include hbs so you double compile all this stuff
    initializer :fix_sprockets_loose_file_searcher, after: :set_default_precompile do |app|
      app.config.assets.precompile.delete(Sprockets::Railtie::LOOSE_APP_ASSETS)
      start_path = ::Rails.root.join("app/assets").to_s
      exclude = ['.es6', '.hbs', '.js', '.css', '']
      app.config.assets.precompile << lambda do |logical_path, filename|
        filename.start_with?(start_path) &&
        !exclude.include?(File.extname(logical_path))
      end
    end

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    config.time_zone = 'UTC'

    # auto-load locales in plugins
    # NOTE: we load both client & server locales since some might be used by PrettyText
    config.i18n.load_path += Dir["#{Rails.root}/plugins/*/config/locales/*.yml"]

    # Configure the default encoding used in templates for Ruby 1.9.
    config.encoding = 'utf-8'

    # Configure sensitive parameters which will be filtered from the log file.
    config.filter_parameters += [
        :password,
        :pop3_polling_password,
        :api_key,
        :s3_secret_access_key,
        :twitter_consumer_secret,
        :facebook_app_secret,
        :github_client_secret
    ]

    # Enable the asset pipeline
    config.assets.enabled = true

    # Version of your assets, change this if you want to expire all your assets
    config.assets.version = '1.2.4'

    # We need to be able to spin threads
    config.active_record.thread_safe!

    # see: http://stackoverflow.com/questions/11894180/how-does-one-correctly-add-custom-sql-dml-in-migrations/11894420#11894420
    config.active_record.schema_format = :sql

    config.active_record.raise_in_transactional_callbacks = true

    # per https://www.owasp.org/index.php/Password_Storage_Cheat_Sheet
    config.pbkdf2_iterations = 64000
    config.pbkdf2_algorithm = "sha256"

    # rack lock is nothing but trouble, get rid of it
    # for some reason still seeing it in Rails 4
    config.middleware.delete Rack::Lock

    # ETags are pointless, we are dynamically compressing
    # so nginx strips etags, may revisit when mainline nginx
    # supports etags (post 1.7)
    config.middleware.delete Rack::ETag

    # route all exceptions via our router
    config.exceptions_app = self.routes

    # Our templates shouldn't start with 'discourse/templates'
    config.handlebars.templates_root = 'discourse/templates'
    config.handlebars.raw_template_namespace = "Discourse.RAW_TEMPLATES"

    require 'discourse_redis'
    require 'logster/redis_store'
    require 'freedom_patches/redis'
    # Use redis for our cache
    config.cache_store = DiscourseRedis.new_redis_store
    $redis = DiscourseRedis.new
    Logster.store = Logster::RedisStore.new(DiscourseRedis.new)

    # we configure rack cache on demand in an initializer
    # our setup does not use rack cache and instead defers to nginx
    config.action_dispatch.rack_cache =  nil

    # ember stuff only used for asset precompliation, production variant plays up
    config.ember.variant = :development
    config.ember.ember_location = "#{Rails.root}/vendor/assets/javascripts/production/ember.js"
    config.ember.handlebars_location = "#{Rails.root}/vendor/assets/javascripts/handlebars.js"

    require 'auth'
    Discourse.activate_plugins! unless Rails.env.test? and ENV['LOAD_PLUGINS'] != "1"

    if GlobalSetting.relative_url_root.present?
      config.relative_url_root = GlobalSetting.relative_url_root
    end

    require_dependency 'stylesheet/manager'

    config.after_initialize do
      # require common dependencies that are often required by plugins
      # in the past observers would load them as side-effects
      # correct behavior is for plugins to require stuff they need,
      # however it would be a risky and breaking change not to require here
      require_dependency 'category'
      require_dependency 'post'
      require_dependency 'topic'
      require_dependency 'user'
      require_dependency 'post_action'
      require_dependency 'post_revision'
      require_dependency 'notification'
      require_dependency 'topic_user'
      require_dependency 'group'
      require_dependency 'user_field'
      require_dependency 'post_action_type'
      # Ensure that Discourse event triggers for web hooks are loaded
      require_dependency 'web_hook'

      # So open id logs somewhere sane
      OpenID::Util.logger = Rails.logger
      if plugins = Discourse.plugins
        plugins.each{|plugin| plugin.notify_after_initialize}
      end
    end

    if ENV['RBTRACE'] == "1"
      require 'rbtrace'
    end

    config.generators do |g|
      g.test_framework :rspec, fixture: false
    end

  end
end

if defined?(PhusionPassenger)
  PhusionPassenger.on_event(:starting_worker_process) do |forked|
    if forked
      Discourse.after_fork
    end
  end
end
