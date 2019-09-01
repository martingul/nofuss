require 'hashids'
require 'base64'
require 'mimemagic'
require 'redcarpet'

module Threads
  def self.submit(req, session)
    thread = req.params['thread']
    edit = req.params['edit'].to_s == 'true'

    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')

    # GET
    if !req.post?
      env = { invalid: false, reply: false, undelete: false, session: session }
      if !thread.nil?
        # verify that thread exists
        id = hashids.decode(thread)[0]
        t = get_thread(id)
        return Router.not_found if t.nil?

        env[:thread] = t
        env[:reply] = true

        # specify if user is allowed to edit the thread
        if edit && session[:username] == t.author
          env[:reply] = false
        end
      end

      return View.finalize('submit', 200, env)
    end

    # POST
    text = req.params['text']
    file = req.params['file']
    delete = req.params['delete'].to_s == 'true'
    undelete = req.params['undelete'].to_s == 'true'

    if !delete && !undelete
      if text.nil? || (text.empty? && file.nil?)
        raise(StandardError, 'invalid_submission')
      end
    end

    hash = nil
    new_hash = false
    if !thread.nil?
      # verify that thread exists
      id = hashids.decode(thread)[0]
      t = get_thread(id)
      return Router.not_found if t.nil?

      if edit
        # verify that user is allowed to edit
        if t.author != session[:username]
          raise(StandardError, 'edit_forbidden')
        end

        edit_thread(t, text, file)
        hash = thread
      elsif delete
        # verify that user is allowed to delete
        if t.author != session[:username]
          raise(StandardError, 'delete_forbidden')
        end

        toggle_thread(t, true)
        hash = thread
      elsif undelete
        # verify that user is allowed to undelete
        if t.author != session[:username]
          raise(StandardError, 'undelete_forbidden')
        end

        edit_thread(t, text, file)
        toggle_thread(t, false)
        hash = thread
      else
        new_hash = true
      end
    else
      new_hash = true
    end

    if new_hash
      hash = create_thread({
        author: session[:id],
        text: text,
        file: file,
        parent: thread
      }, !thread.nil?)
    end

    return thread(hash, false, session, true) # redirect to thread
  rescue => e
    puts e.inspect
    puts e.backtrace.join("\n")

    env = { invalid: true, session: session }
    headers = {}

    if !thread.nil? && edit && e.message != 'edit_forbidden'
      if t.nil?
        id = hashids.decode(thread)[0]
        t = get_thread(id)
      end

      env[:thread] = t
      # choice here: 1) either redirect the user, but we'll have to pass the
      # value of `invalid` to display on the form with a GET parameter for
      # example or 2) don't redirect but the user will lose
      # the `?thread=...&edit=true` part of the URL even if he'll still be
      # editing the same thread
      # headers = { 'Location' => "/submit?thread=#{t.hash}&edit=true" }
    end

    if e.message == 'edit_forbidden'
      headers = { 'Location' => "/thread/#{t.hash}"} # redirect to thread
    end

    return View.finalize('submit', headers.nil? ? 400 : 302, env, headers)
  ensure
    if !file.nil? && !file[:tempfile].nil?
      file[:tempfile].close
      file[:tempfile].unlink
    end
  end

  def self.thread(hash, edit, session, redirect = false)
    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    id = hashids.decode(hash)[0]

    thread = get_thread(id)
    return Router.not_found if thread.nil?

    status = 200
    headers = {}
    if redirect
      location = "/thread/#{hash}"
      headers['Location'] = location
      status = 302
    end

    return View.finalize('thread', status, {
      thread: thread, edit: edit, session: session
    }, headers)
  end

  # return whether a thread exists or not
  def self.exists?(id)
    return false if id.nil?

    $db.execute('select exists (select 1 from threads 
                where threads.rowid = ? limit 1)', [id])

    exists = rs[0]['exists']
    return exists
  end

  # create a thread in database and return its hash
  def self.create_thread(thread, reply = false)
    ext = get_file_ext(thread[:file]) if !thread[:file].nil?

    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    parent = hashids.decode(thread[:parent])[0]
    return if reply && !exists?(parent)

    # create thread in database
    $db.execute('insert into threads(author, text, ext) values(?, ?, ?)',
                [thread[:author], thread[:text], ext])

    # get newly inserted thread id
    rs = $db.execute('select rowid as id from threads where author = ?
                     order by date_created desc limit 1', [thread[:author]])

    id = rs[0]['id']
    add_child(parent, id) if reply && !parent.nil?

    hash = hashids.encode(id)
    create_file("#{hash}.#{ext}", thread[:file]) if !ext.nil?

    return hash
  end

  # update a thread in database
  def self.edit_thread(thread, new_text, new_file)
    ext = get_file_ext(new_file) if !new_file.nil?

    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    id = hashids.decode(thread.hash)[0]

    if ext.nil?
      # get current file extension
      rs = $db.execute('select threads.ext from threads
                       where threads.rowid = ?', [id])
      old_ext = rs[0]['ext']
    end

    $db.execute('update threads set text = ?, ext = ? where threads.rowid = ?',
                [new_text, ext.nil? ? old_ext : ext, id])

    if !new_file.nil?
      if !old_ext.nil?
        File.delete("./public/file/#{thread.hash}.#{old_ext}")
      end

      create_file("#{thread.hash}.#{ext}", new_file) if !new_file.nil?
    end
  end

  # toggle the deleted status of a thread (delete or undelete)
  def self.toggle_thread(thread, deleted)
    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    id = hashids.decode(thread.hash)[0]

    $db.execute('update threads set deleted = ? where threads.rowid = ?',
               [deleted ? 1 : 0, id])
  end

  # add a child to a parent thread in database
  def self.add_child(parent, child)
    # add the child thread to the parent thread's children array
    $db.execute('update threads
                set children = array_append(threads.children, ?)
                where threads.rowid = ?', [child, parent])

    # set the child thread's parent to be the parent thread
    $db.execute('update threads set parent = ?
                where threads.rowid = ?', [parent, child])
  end

  # return a file's extension by reading its content
  def self.get_file_ext(file)
    allowed_mimes = {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/gif' => 'gif',
    }

    tmp = file[:tempfile]
    mime = MimeMagic.by_magic(tmp) # detect mime type
    ext = allowed_mimes["#{mime}"]

    raise(StandardError, 'invalid_file') if ext.nil?
    return ext
  end

  # create a file on disk
  def self.create_file(name, file)
    # TODO check result of disk operation
    disk_file = File.open("./public/file/#{name}", 'w') { |f|
      f.write(file[:tempfile].read)
    }
  end

  def self.get_threads
    rs = $db.execute('select threads.rowid as id, users.username as author, 
                      threads.text, threads.ext, threads.children,
                      threads.date_created from threads
                      join users on users.rowid = threads.author
                      where threads.parent is null and not threads.deleted
                      order by threads.date_created desc limit 20')

    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    threads = []
    rs.each { |r|
      children = []
      if !r['children'].nil?
        #.tr('{}', '').split(',').map{ |c| c.to_i }
        children = []
      end

      threads.push(Render::Thread.new(
        hash: hashids.encode(r['id']),
        author: r['author'],
        text: r['text'],
        ext: r['ext'],
        parent: r['parent'],
        children: children,
        date_created: date_as_sentence(r['date_created'])
      ))
    }

    return threads
  end

  # return a thread from database
  def self.get_thread(id)
    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')

    # return a thread with a list of integers as children
    rs = $db.execute('select threads.rowid as id, threads.deleted,
                      users.username as author, threads.text, threads.ext,
                      threads.parent, threads.children, threads.date_created
                      from threads join users on users.rowid = threads.author
                      where threads.rowid = ? limit 1', [id])

    return if rs.empty? # thread not found
    r = rs[0]
  
    children = []
    if !r['children'].nil?
      children = []
    end

    return Render::Thread.new(
      hash: hashids.encode(r['id']),
      deleted: r['deleted'] == 1,
      author: r['author'],
      text: r['text'],
      ext: r['ext'],
      parent: r['parent'].nil? ?
        nil : hashids.encode(r['parent']),
      children: children,
      date_created: date_as_sentence(r['date_created'])
    )
  end

  # convert a date to a 'X time ago' type sentence
  # TODO mode this function into a utils module
  def self.date_as_sentence(date)
    d = Time.at(date)
    t_now = Time.now
    dt = t_now - d

    datetime = [
      dt, # seconds
      dt/60, # minutes
      dt/(60*60), # hours
      dt/(60*60*24), # days
      dt/(60*60*24*7), # weeks
      dt/(60*60*24*7*52), # years
    ]

    units = {
      1 => "seconds", 2 => "minutes",
      3 => "hours",   4 => "days",
      5 => "weeks",   6 => "years"
    }

    datetime = datetime.take_while { |i| i >= 1 }.map { |i| i = i.truncate(0) }
    datetime.push 1 if datetime.empty? # 1 second ago
    unit = units[datetime.length] # select corresponding unit
    unit[-1] = '' if datetime[datetime.length - 1] == 1 # check for singularity

    return "#{datetime[datetime.length - 1]} #{unit} ago"
  end
end
