require 'ostruct'

class View
  def initialize(page, env = {})
    @env = env # TODO validate each field
    @page = page
    @template = File.read(File.expand_path("assets/views/#{page}.html.erb"))
  end

  def render
    ERB.new(@template).result(binding)
  end

  def include(view)
    ERB.new(
      File.read(File.expand_path("assets/views/#{view}.html.erb"))
    ).result(binding)
  end
  
  def self.finalize(view_name, status = 200, env = {}, headers = {})
    view = View.new(view_name, env)
    body = view.render
    _headers = {'Content-Type' => 'text/html'}
    _headers.merge!(headers)

    return Rack::Response.new(body, status, _headers)
  end
end
