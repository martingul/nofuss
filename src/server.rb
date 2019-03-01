require 'rack'
require 'erb'
require 'pg'
require './src/view.rb'
require './src/router.rb'

class Server
  def call(env)
    # Route request
    req = Rack::Request.new(env)
    return Router.route(req)
  end
end
