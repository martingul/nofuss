module Render
  class Thread
    def initialize(thread)
      @hash = thread[:hash]
      @author = thread[:author]
      @text = thread[:text]
      @ext = thread[:ext]
      @parent = thread[:parent]
      @children = thread[:children]
      @date_created = thread[:date_created]
      @html = ''
    end

    def render(depth, with_reply = false, is_logged = false)
      parser = get_parser
      template = <<~HTML
        <div class="thread"
          <% if depth > 0 %>
            style="margin-left: <%= 10*depth %>px"
          <% end %>
          <% if depth == -1 && @children.length > 0 %>
            style="margin-bottom: 15px;"
          <% end %>>
          <div class="thread-header">
            <a href="/user/<%= @author %>">
              <b><%= @author %></b></a>
            <span><%= @hash %></span>
            <a href="/thread/<%= @hash %>">
              <%= @date_created %> (<%= @children.length %>
              child<% if @children.length != 1 %>ren<% end %>)</a>
            <% if !@parent.nil? && depth == -1 %>
              <a href="/thread/<%= @parent %>">parent</a>
            <% end %>
            <% if with_reply %>
              <% if !is_logged %>
              <a href="/login">reply</a>
              <% else %>
              <label for="reply-<%= @hash %>">reply</label>
              <% end %>
            <% else %>
              <a href="/thread/<%=@hash %>">reply</a>
            <% end %>
          </div>
          <div class="thread-content">
            <% if !@ext.nil? %>
            <div>
              <a href="/file/<%= "#{@hash}.#{@ext}" %>">
                <img src="/file/<%= "#{@hash}.#{@ext}" %>"></a>
            </div>
            <% end %>
            <% if !@text.nil? %>
            <div class="text">
              <%= parser.render(@text) %>
            </div>
            <% end %>
          </div>
      HTML

      if with_reply && is_logged
        # append reply form
        template += <<~HTML
          <div class="thread-reply">
            <input class="switch" type="checkbox" id="reply-<%= @hash %>"
            name="reply-<%= @hash %>">
            <div id="replyform-<%= @hash %>">
              <style>
                #replyform-<%= @hash %> {
                  display: none;
                }
                input#reply-<%= @hash %>:checked + #replyform-<%= @hash %> {
                  display: block;
                }
              </style>
              <%= Reply.render(@hash) %>
            </div>
          </div>
        HTML
      end

      template += <<~HTML
        </div>
      HTML

      return ERB.new(template).result(binding)
    end

    # recursively render the thread and retrieve its children
    # TODO implement a maximum depth
    def recursive_render(depth, is_logged = false)
      if @children.length > 0
        @children.collect! { |child| Threads.get_thread(child) }
      end

      @html += render(depth, true, is_logged)

      if @children.length > 0
        @children.each { |child|
          @html += child.recursive_render(depth + 1, is_logged)
        }
      end

      return @html
    end

    # return a markdown parser for text rendering
    def get_parser
      renderer = Redcarpet::Render::HTML.new(
        no_styles: true,
        no_images: true,
        filter_html: true,
        escape_html: true,
        hard_wrap: true
      )
      return Redcarpet::Markdown.new(renderer,
        disable_indented_code_blocks: true,
        fenced_code_blocks: true,
        space_after_headers: true,
        strikethrough: true,
        underline: true,
        quote: true,
        lax_spacing: true
      )
    end
  end

  class Reply
    def self.render(parent = nil, incorrect = false)
      template = <<~HTML
        <div>
          <% if incorrect %>
          <div class="error">incorrect</div>
          <% end %>
          You can submit some text
          <a href="https://en.wikipedia.org/wiki/Markdown#Example" target="_blank">
            (markdown)</a> and/or a file (image, gif, video)
          <% if !parent.nil? %>
          <form method="post" action="/submit?thread=<%= parent %>" enctype="multipart/form-data">
          <% else %>
          <form method="post" action="/submit" enctype="multipart/form-data">
          <% end %>
            <textarea id="text" name="text" spellcheck="false"></textarea>
            <input type="file" name="file" id="name" accept=".jpg,.gif">
            <input type="submit" value="submit">
          </form>
        </div>
      HTML

      return ERB.new(template).result(binding)
    end
  end

  class Header
    def self.render(session)
      template = <<~HTML
        <div class="header">
          <a href="/" class="title action">Frontpage</a>
          <% if !session.nil?%>
            <a href="/submit" class="action">submit</a>
          <% end %>
          <span class="right">
            <% if session.nil? %>
              <a href="/login">login</a>
            <% else %>
              <a href="/user/<%= session[:username] %>" class="action">
                <%= session[:username] %></a>
              <a href="/logout">logout</a>
            <% end %>
          </span>
        </div>
      HTML

      return ERB.new(template).result(binding)
    end
  end
end
