require 'erb'
require './src/render'

class View
  def initialize(page, env = {})
    @env = env
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

  def self.finalize(view_name, status = 200, env = {}, _headers = {})
    view = View.new(view_name, env)
    body = view.render
    headers = {'Content-Type' => 'text/html'}
    headers.merge!(_headers)

    return Rack::Response.new(body, status, headers)
  end
end
