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
    attr_reader :hash, :deleted, :author, :title, :text, :ext, :date_created
    attr_accessor :children

    def initialize(thread)
      @hash = thread[:hash]
      @deleted = thread[:deleted]
      @author = thread[:author]
      @title = thread[:title]
      @text = thread[:text]
      @ext = thread[:ext]
      @parent = thread[:parent]
      @children = thread[:children]
      @date_created = thread[:date_created]
      @html = ''
    end

    def render(depth, with_reply = false, session = nil)
      is_author = false
      if !session.nil?
        is_logged = true
        is_author = session[:username] == @author
      end

      parser = Render.get_parser
      template = <<~HTML
        <div class="thread" id="<%= @hash %>"
          <% if is_author || depth > 0 %>
            style="
            <% if depth > 0 %>
              margin-left: <%= 10*depth %>px; border-left: 1px dotted #666;
            <% end %>
            <% if is_author %>
              background: #fdfff2;
            <% end %>"
          <% end %>>
          <div class="thread-header">
            <% if @deleted && !is_author %>
              <b>[deleted]</b>
            <% else %>
            <a href="/user/<%= @author %>">
              <b><%= @author %></b></a>
            <% end %>
            <a href="/thread/<%= @hash %>">
              <%= @date_created %> (<%= @children.length %>
              child<% if @children.length != 1 %>ren<% end %>)</a>
            <% if !@parent.nil? && depth == -1 %>
              <a href="/thread/<%= @parent %>">parent</a>
            <% end %>
            <% if !@deleted %>
              <% if with_reply %>
                <% if !is_logged %>
                <a href="/login">reply</a>
                <% else %>
                <label class="trigger" for="reply-<%= @hash %>">
                  reply</label>
                <% end %>
              <% end %>
              <% if is_author %>
                <a href="/submit?thread=<%= @hash %>&edit=true">edit</a>
              <% end %>
            <% else %>
              <% if is_author %>
                <span class="info">[deleted]</span>
                <a href="/submit?thread=<%= @hash %>&edit=true">
                  undelete</a>
              <% end %>
            <% end %>
          </div>
          <%= @title %>
          <div class="thread-content">
            <% if @deleted && !is_author %>
              [deleted]
            <% else %>
              <% if !@ext.nil? %>
              <div>
                <a href="/file/<%= @hash %>.<%= @ext %>">
                  <img class="thumbnail" alt="<%= @hash %>.<%= @ext %>"
                    title="<%= @hash %>.<%= @ext %>"
                    src="/file/<%= @hash %>.<%= @ext %>">
                </a>
              </div>
              <% end %>
              <% if !@text.nil? %>
              <div class="text">
                <%= parser.render(@text) %>
              </div>
              <% end %>
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
          <span class="name">replies</span>
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
          if !child.nil?
            @html += child.recursive_render(depth + 1, session)
          end
        }
      end

      return @html
    end
  end

  class Textbox
    def self.render(thread = nil, invalid = false, reply = false, title = false)
      template = <<~HTML
        <div>
          <div class="textbox-header">
            <% if invalid %>
            <div class="error margin">invalid submission</div>
            <% end %>
            <% if !thread.nil? && !reply && !thread.deleted %>
            <form method="post" action="/submit">
              <input type="hidden" name="thread"
                value="<%= thread.hash %>">
              <input type="hidden" name="delete" value="true">
              <input type="submit" value="delete"
                style="margin-top: -2px;">
            </form>
            <% end %>
          </div>
          <form method="post" action="/submit" enctype="multipart/form-data">
            <% if title %>
            <input type="text" name="title"
              placeholder="title" spellcheck="false"
              <% if !thread.nil? && !reply %>
              value="<%= thread.title %>"
              <% end %>>
            <% end %>
            <span class="info">
            you can submit text
            <a href="https://en.wikipedia.org/wiki/Markdown#Example"
              target="_blank">
              (markdown)</a> and/or a file (image, gif, video)
            </span>
            <% if !thread.nil? && !reply %>
            <textarea id="text" name="text" spellcheck="false"><%=
              thread.text
            %></textarea>
            <div class="textbox-footer">
              <% if !thread.ext.nil? %>
              <span>
                <a href="/file/<%= thread.hash %>.<%= thread.ext %>">
                <img class="thumbnail-small"
                  alt="<%= thread.hash %>.<%= thread.ext %>"
                  title="<%= thread.hash %>.<%= thread.ext %>"
                  src="/file/<%= thread.hash %>.<%= thread.ext %>"></a>
              </span>
              <% end %>
            <% else %>
            <textarea id="text" name="text" spellcheck="false"></textarea>
            <div class="textbox-footer">
            <% end %>
            <span>
              <input type="file" name="file" accept=".jpg,.gif">
            </span>
            <span>
              <% if thread.nil? %>
              <input type="submit" value="submit">
              <% else %>
              <input type="hidden" name="thread"
                value="<%= thread.hash %>">
                <% if reply %>
                <input type="submit" value="submit">
                <% elsif thread.deleted %>
                <input type="hidden" name="undelete" value="true">
                <input type="submit" value="undelete">
                <% else %>
                <input type="hidden" name="edit" value="true">
                <input type="submit" value="edit">
                <% end %>
              <% end %>
            </span>
            </div>
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
