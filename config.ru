require 'pg'
require 'connection_pool'
require './src/server'

$db = ConnectionPool::Wrapper.new(size: 5, timeout: 5) {
  PG.connect(dbname: 'storage')
}

use Rack::Static, :urls => ['/file'], :root => "public"
run Server.new
