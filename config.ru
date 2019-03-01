require './src/server.rb'

use Rack::Static, :urls => ['/css', '/f'], :root => "assets"
run Server.new
