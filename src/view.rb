require 'erb'

class Thread
  def self.render(thread, depth, parser, with_reply = false)
    template = <<-HTML
      <div class="thread"
        <% if depth > 0 %>
          style="margin-left: <%= 10*depth %>px"
        <% end %>>
        <div class="thread-header">
          <a href="/user/<%= thread[:author] %>">
            <b><%= thread[:author] %></b></a>
          <a href="/thread/<%= thread[:hash] %>">
            <%= thread[:date_created] %> (<%= thread[:children].length %>
            child<% if thread[:children].length != 1 %>ren<% end %>)</a>
          <% if !thread[:parent].nil? && depth == -1 %>
            <a href="/thread/<%= thread[:parent] %>">parent</a>
          <% end %>
          <% if with_reply %>
            <label for="reply-<%= thread[:hash] %>">reply</label>
          <% else %>
            <a href="/thread/<%=thread[:hash] %>">reply</a>
          <% end %>
        </div>
        <div class="thread-content">
          <% if !thread[:ext].nil? %>
          <div>
            <a href="/file/<%= "#{thread[:hash]}.#{thread[:ext]}" %>">
              <img src="/file/<%= "#{thread[:hash]}.#{thread[:ext]}" %>"></a>
          </div>
          <% end %>
          <% if !thread[:text].nil? %>
          <div class="text">
            <%= parser.render(thread[:text]) %>
          </div>
          <% end %>
        </div>
      </div>
    HTML
    if with_reply
      template += <<-HTML
        <input class="switch" type="checkbox" id="reply-<%= thread[:hash] %>"
        name="reply-<%= thread[:hash] %>">
        <form id="replyform-<%= thread[:hash] %>">
          <style>
            #replyform-<%= thread[:hash] %> {
              display: none;
            }
            input#reply-<%= thread[:hash] %>:checked
              + #replyform-<%= thread[:hash] %> {
              display: block;
            }
          </style>
          <textarea id="comment" name="comment"></textarea>
          <input type="submit" value="reply">
        </form>
      HTML
    end

    template += <<-HTML
      <% if depth == -1 %>
      <div class="margin">
        <b>replies</b>
      </div>
      <% end %>
    HTML

    return ERB.new(template).result(binding)
  end

  def self.recursive_render(thread, depth, parser)
    res = render(thread, depth, parser, true)

    if thread[:children].length > 0
      thread[:children].each do |child|
        res += recursive_render(child, depth + 1, parser)
      end
    end

    return res
  end
end

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
