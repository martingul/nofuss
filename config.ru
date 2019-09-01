require 'sqlite3'
require './src/server'

begin
  $db = SQLite3::Database.new 'storage.db'
  $db.results_as_hash = true

  use Rack::Static, :urls => ['/file', '/fonts'], :root => "public"
  run Server.new
end
