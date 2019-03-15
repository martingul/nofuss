require 'erb'
require './src/render'

class View
  def initialize(page, env = {})
    @env = env # TODO validate each field
    @page = page
    @template = File.read(File.expand_path("public/view/#{page}.html.erb"))
  end

  def render
    return ERB.new(@template).result(binding)
  end

  def include(view)
    return ERB.new(
      File.read(File.expand_path("public/view/include/#{view}.html.erb"))
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
