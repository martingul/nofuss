require 'hashids'
require 'base64'
require 'mimemagic'
require 'redcarpet'

module Threads
  def self.create_thread(thread, reply = false)
    allowed_mimes = {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/gif' => 'gif',
    }

    ext = nil
    if !thread[:file].nil?
      tmp = File.open(thread[:file][:tempfile].path, 'r')
      # TODO check result of disk operations
      # detect mime type and extension
      mime = MimeMagic.by_magic(tmp)
      ext = allowed_mimes["#{mime}"]

      return nil if ext.nil? # file not allowed
    end

    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    parent = nil

    if reply
      # verify that parent thread exists
      parent = hashids.decode(thread[:parent])[0]
      seed = Random.new_seed.to_s
      $db.prepare('threads1',
        'SELECT EXISTS
          (SELECT 1
          FROM threads
          WHERE threads.id = $1 LIMIT 1)')
      result = $db.exec_prepared(seed, [parent])
      exists = result.column_values(0)[0]
      result.clear

      return nil if !exists # parent thread not found
    end

    # create thread in database
    seed = Random.new_seed.to_s
    $db.prepare(seed,
      'INSERT INTO threads(author, text, ext)
      VALUES($1, $2, $3) RETURNING id')
    result = db.exec_prepared(seed, [
      thread[:author], thread[:text], ext
    ]) # TODO check result
    id = result[0]['id']

    if reply && !parent.nil?
      # add the new thread to the parent thread's children
      seed1 = Random.new_seed.to_s
      $db.prepare(seed1,
        'UPDATE threads
        SET children = array_append(threads.children, $1)
        WHERE threads.id = $2')

      # set the new thread's parent to be the parent thread
      seed2 = Random.new_seed.to_s
      $db.prepare(seed2,
        'UPDATE threads
        SET parent = $1
        WHERE threads.id = $2')

      result = $db.exec_prepared(seed1, [id, parent])
      result = $db.exec_prepared(seed2, [parent, id])
      # TODO check result
    end

    result.clear

    hash = hashids.encode(id)
    if !thread[:file].nil?
      f = File.open("public/file/#{hash}.#{ext}", 'w') { |i| i.write(tmp.read) }
      # TODO think about closing the temp file
    end

    return hash
  end

  def self.submit(req, session)
    if !req.post?
      return View.finalize('submit', 200, { incorrect: false, session: session })
    end

    text = req.params['text']
    file = req.params['file']
    parent = req.params['thread']
    # TODO validate each input

    if text.empty? && file.nil?
      return View.finalize('submit', 400, { incorrect: true, session: session })
    end

    hash = create_thread({
      author: session[:id],
      text: text,
      file: file,
      parent: parent
    }, !parent.nil?)

    return thread(hash, session, true) # redirect to the thread
  end

  def self.get_threads
    seed = Random.new_seed.to_s
    $db.prepare(seed,
      'SELECT threads.id, users.username AS author, threads.text, threads.ext,
      threads.children::int[], threads.date_created
      FROM threads
      JOIN users ON users.id = threads.author
      WHERE threads.parent IS NULL
      ORDER BY threads.date_created DESC LIMIT 20')
    result = $db.exec_prepared(seed, []) #  TODO check result

    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    threads = []
    result.each_row { |row|
      threads.push(Render::Thread.new(
        hash: hashids.encode(row[0].to_i),
        author: row[1], text: row[2], ext: row[3], parent: nil,
        children: row[4].tr('{}', '').split(',').map{ |c| c.to_i },
        date_created: date_as_sentence(row[5])
      ))
    }

    result.clear
    return threads
  end

  # retrieve a thread from its hash
  def self.thread(hash, session, redirect = false)
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
      thread: thread, session: session
    }, headers)
  end

  # get a thread from database
  def self.get_thread(id)
    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')

    # return a thread with a list of integers as children
    seed = Random.new_seed.to_s
    $db.prepare(seed,
      'SELECT threads.id, users.username AS author, threads.text, threads.ext,
      threads.parent, threads.children::int[], threads.date_created
      FROM threads
      JOIN users ON users.id = threads.author
      WHERE threads.id = $1 LIMIT 1')
    result = $db.exec_prepared(seed, [id]) # TODO check result

    return if result.column_values(0).empty? # thread not found

    return Render::Thread.new(
      hash: hashids.encode(result.column_values(0)[0].to_i),
      author: result.column_values(1)[0],
      text: result.column_values(2)[0],
      ext: result.column_values(3)[0],
      parent: result.column_values(4)[0].nil? ?
        nil : hashids.encode(result.column_values(4)[0].to_i),
      children: result.column_values(5)[0].tr('{}', '')
        .split(',').map{ |c| c.to_i },
      date_created: date_as_sentence(result.column_values(6)[0])
    )
  end

  # convert a date to a 'X time ago' type sentence
  def self.date_as_sentence(date)
    d = Time.parse(date)
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
