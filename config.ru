require 'pg'
require 'connection_pool'
require 'yaml'
require './src/server'

class ConfigError < StandardError
  def initialize(message)
    super(message)
  end
end

def validate_config(config)
  database_valid = true
  if !config['database'].nil?
    if config['database']['name'].nil?
      database_valid = false
    end
  else
    database_valid = false
  end

  pool_valid = true
  if !config['pool'].nil?
    if config['pool']['size'].nil? || config['pool']['timeout'].nil?
      pool_valid = false
    end
  else
    pool_valid = false
  end

  return {
    valid: database_valid && pool_valid,
    database_valid: database_valid,
    pool_valid: pool_valid
  }
end

def load_config
  config = YAML.load(File.read('config.yml'))
  v = validate_config(config)

  if !v[:valid]
    raise ConfigError.new('database') if !v[:database_valid]
    raise ConfigError.new('pool') if !v[:pool_valid]
  end

  return config
rescue SystemCallError => e
  abort('ERROR file config.yml not found') if e.errno == Errno::ENOENT::Errno
rescue ConfigError => e
  puts e.inspect
  STDERR.puts "ERROR in #{e.message} configuration (config.yml)"

  exit(1) if e.message == 'database'
  config['pool'] = { 'size' => 5, 'timeout' => 5 } if e.message == 'pool'

  return config
end

begin
  config = load_config

  $db = ConnectionPool::Wrapper.new(
    size: config['pool']['size'], timeout: config['pool']['timeout']
    ) do
      PG.connect(
        host: config['database']['host'],
        port: config['database']['port'],
        dbname: config['database']['name'],
        user: config['database']['user'],
        password: config['database']['password']
      )
    rescue PG::ConnectionBad => e
      STDERR.puts(
        "ERROR connecting to the database #{config['database']['name']}"
      )
    end

  use Rack::Static, :urls => ['/file'], :root => "public"
  run Server.new
end
