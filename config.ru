require './src/server.rb'

use Rack::Static, :urls => ['/file'], :root => "public"
run Server.new
