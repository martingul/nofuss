require 'rack'
require 'pp'
require './src/router'
require './src/view'

class Server
  def call(env)
    req = Rack::Request.new(env)
    return Router.route(req)
  end
end
