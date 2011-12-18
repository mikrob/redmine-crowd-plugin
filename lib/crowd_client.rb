require 'rubygems'
require 'crowd'

class CrowdClient

  @@authenticated = nil
  @@cookie_name = nil
  @@url = nil
  @@login = nil
  @@password = nil
  @@cookie_name = nil
  
  def self.configure url, login, password, cookie_name
    return if @@authenticated && url == @@url && login == @@login && password == @@password && cookie_name == @@cookie_name
    Crowd.crowd_url = url
    Crowd.crowd_app_name = login
    Crowd.crowd_app_pword = password
    @@url = url
    @@login = login
    @@password = password
    @@cookie_name = cookie_name
    puts "Authenticating app to crowd"
    @@authenticated = Crowd.authenticate_application rescue nil
    puts "Result : #{self.app_ready?}"
  end

  def self.app_ready?
    @@authenticated ? true : false
  end

  def self.authenticate_principal session, request
    token = request.cookies[@@cookie_name]
    return false unless token
    user_agent = request.env['HTTP_USER_AGENT']
    remote_address = request.env['HTTP_X_FORWARDED_FOR'] || request.env['REMOTE_ADDR']
    unless Crowd.is_valid_principal_token? token, {"User-Agent" => user_agent, "remote_address" => remote_address}
      return false
    end
    session[:crowd_principal_info] = Crowd.find_principal_by_token(token)
    session[:crowd_user] = session[:crowd_principal_info][:name]
    true
  end

  def self.logout session, request
    token = request.cookies[@@cookie_name]
    return false unless token
    Crowd.invalidate_principal_token token
  end

end
