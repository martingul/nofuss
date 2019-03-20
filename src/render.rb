module Render
  # return a markdown parser for text rendering
  def self.get_parser
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

  class Thread
    attr_reader :hash, :author, :text, :date_created
    attr_accessor :children

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

    def render(depth, with_reply = false, session = nil)
      is_logged = !session.nil?
      is_author = false
      if is_logged
        is_author = session[:username] == @author
      end

      parser = Render.get_parser
      template = <<~HTML
        <div class="thread"
          <% if depth > 0 %>
            style="margin-left: <%= 10*depth %>px"
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
              <label class="trigger" for="reply-<%= @hash %>">reply</label>
              <% end %>
            <% else %>
              <a href="/thread/<%= @hash %>">reply</a>
            <% end %>
            <% if is_author %>
              <a href="/submit?thread=<%= @hash %>&edit=true">edit</a>
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
              <%= Textbox.render(self, false, true) %>
            </div>
          </div>
        HTML
      end

      template += <<~HTML
        </div>
        <% if depth == -1 && @children.length > 0 %>
        <div class="separator">
          replies
        </div>
        <% end %>
      HTML

      return ERB.new(template).result(binding)
    end

    # recursively render the thread and retrieve its children
    # TODO implement a maximum depth
    def recursive_render(depth, session = nil)
      if @children.length > 0
        @children.collect! { |child| Threads.get_thread(child) }
      end

      @html += render(depth, true, session)

      if @children.length > 0
        @children.each { |child|
          @html += child.recursive_render(depth + 1, session) if !child.nil?
        }
      end

      return @html
    end
  end

  class Textbox
      def self.render(thread = nil, invalid = false, reply = false)
      template = <<~HTML
        <div>
          <% if invalid %>
          <div class="error margin">invalid submission</div>
          <% end %>
          <div class="info">
            you can submit text
            <a href="https://en.wikipedia.org/wiki/Markdown#Example" target="_blank">
              (markdown)</a> and/or a file (image, gif, video)
          </div>
          <form method="post" action="/submit" enctype="multipart/form-data">
            <% if !thread.nil? && !reply %>
            <textarea id="text" name="text" spellcheck="false"><%= thread.text %></textarea>
            <% else %>
            <textarea id="text" name="text" spellcheck="false"></textarea>
            <% end %>
            <input type="file" name="file" accept=".jpg,.gif">
            <% if !thread.nil? %>
            <input type="hidden" name="thread" value="<%= thread.hash %>">
            <% end %>
            <input type="hidden" name="edit" value="<%= !reply %>">
            <input type="submit" value="<%= thread.nil? || reply ? 'submit' : 'edit' %>">
          </form>
        </div>
      HTML

      return ERB.new(template).result(binding)
    end
  end

  class Header
    def self.render(session = nil)
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
