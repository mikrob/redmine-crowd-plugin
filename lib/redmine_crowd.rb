Redmine::Plugin.register :redmine_crowd do
  name        "Crowd Authentication"
  author      'Bertrand Paquet'
  description "Crow single sign-on service authentication support. Inspired from redmine cas plugin."
  version     '0.0.3'

  # menu        :account_menu,
  #             :login_without_crowd,
  #             {
  #               :controller => 'account',
  #               :action     => 'login_without_crowd'
  #             },
  #             :caption => :login_without_crowd,
  #             :after   => :login,
  #             :if      => Proc.new { RedmineCrowd.ready? && RedmineCrowd.get_setting(:login_without_crowd) && !User.current.logged?
  #             }

  settings :default => {
    :enabled                         => false,
    :crowd_base_url                    => 'https://localhost',
    :crowd_appname                     => '',
    :crowd_appassword                  => '',
    :crowd_cookiename                  => 'crowd.token_key',
    :login_without_crowd             => false,
    :auto_create_users               => false,
    :auto_update_attributes_on_login => false
    :partial => 'settings/settings'
  },

end

# Utility class to simplify plugin usage
class RedmineCrowd

  class << self

    def plugin
      Redmine::Plugin.find(:redmine_crowd)
    end

    # Get plugin setting value or it's default value in a safe way.
    # If the setting key is not found, returns nil.
    # If the plugin has not been registered yet, returns nil.
    def get_setting(name)
      begin
        if plugin
          if Setting["plugin_#{plugin.id}"]
            Setting["plugin_#{plugin.id}"][name]
          else
            if plugin.settings[:default].has_key?(name)
              plugin.settings[:default][name]
            end
          end
        end
      rescue

        # We don't care about exceptions which can actually occur ie. when running
        # migrations and settings table has not yet been created.
        nil
      end
    end

    # Update Crowd configuration using settings.
    # Can be run more than once (it's invoked on each plugin settings update).
    def configure!
      CrowdClient.configure(get_setting(:crowd_base_url), get_setting(:crowd_appname), get_setting(:crowd_apppassword), get_setting(:crowd_cookiename))
    end

    # Is Crowd enabled, client configured and server available
    def ready?
      get_setting(:enabled) && CrowdClient.app_ready?
    end

    # Return User model friendly attributes from Crowd session.
    def user_attributes_by_session(session)
      attributes = {}
      if principal_info = session[:crowd_principal_info]
        attributes[:firstname] = principal_info[:attributes][:givenName]
        attributes[:lastname] = principal_info[:attributes][:sn]
        attributes[:mail] = principal_info[:attributes][:mail]
      end
      attributes
    end

  end

end

# We're using dispatcher to setup Crowd.
# This way we can work in development environment (where to_prepare is executed on every page reload)
# and production (executed once on first page load only).
# This way we're avoiding the problem where Rails reloads models but not plugins in development mode.
if defined?(ActionController)

  Rails::Railtie::Configuration.to_prepare do

    # We're watching for setting updates for the plugin.
    # After each change we want to reconfigure Crowd client.
    Setting.class_eval do
      after_save do
        if name == 'plugin_redmine_crowd'
          RedmineCrowd.configure!
        end
      end
    end

    # Let's (re)configure our plugin according to the current settings
    RedmineCrowd.configure!

    AccountController.class_eval do

      def login_with_crowd
        if params[:username].blank? && params[:password].blank? && RedmineCrowd.ready?
          if session[:user_id]
            true
          else
            if CrowdClient.authenticate_principal(session, request)
              # User has been successfully authenticated with Crowd
              user = User.find_or_initialize_by_login(session[:crowd_user])
              unless user.new_record?

                # ...and also found in Redmine
                if user.active?

                  # ...and user is active
                  if RedmineCrowd.get_setting(:auto_update_attributes_on_login)

                    # Plugin configured to update users from CAS extra user attributes
                    unless user.update_attributes(RedmineCrowd.user_attributes_by_session(session))
                      # TODO: error updating attributes on login from Crowd. We can skip this for now.
                    end
                  end
                  successful_authentication(user)
                else
                  account_pending
                end
              else

                # ...user has been authenticated with CAS but not found in Redmine
                if RedmineCrowd.get_setting(:auto_create_users)

                  # Plugin config says to create user, let's try by getting as much as possible
                  # from CAS extra user attributes. To add/remove extra attributes passed from CAS
                  # server, please refer to your CAS server documentation.
                  user.attributes = RedmineCrowd.user_attributes_by_session(session)
                  user.status = User::STATUS_REGISTERED

                  register_automatically(user) do
                    onthefly_creation_failed(user)
                  end
                else

                  # User auto-create disabled in plugin config
                  flash[:error] = l(:crowd_authenticated_user_not_found, session[:crowd_user])
                  redirect_to home_url
                end
              end
            else

              # Not authenticated with Crowd, hope some on will do something useful with the request
            end
          end
        else
          login_without_crowd
        end
      end

      alias_method_chain :login, :crowd

      def logout_with_crowd
        if RedmineCrowd.ready?
          CrowdClient.logout(session, request)
          logout_user
        else
          logout_without_crowd
        end
      end

      alias_method_chain :logout, :crowd

    end

  end

end
