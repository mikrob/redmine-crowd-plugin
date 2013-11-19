require 'redmine'
require 'redmine_crowd'
require 'crowd_client'


Redmine::Plugin.register :redmine_crowd_plugin do
  settings :default => {'empty' => true}, :partial => 'settings'
end