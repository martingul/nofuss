require 'hashids'
require 'base64'
require 'mimemagic'

module Threads
  def self.create_thread(thread, reply = false)
    allowed_mimes = {
      'image/jpeg' => 'jpg',
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
    db = PG.connect(dbname: 'storage')

    parent = nil
    if reply
      # verify that parent thread exists
      parent = hashids.decode(thread[:parent])[0]
      db.prepare('threads1',
        'SELECT EXISTS
          (SELECT 1
          FROM threads
          WHERE threads.id = $1 LIMIT 1)')
      result = db.exec_prepared('threads1', [parent])
      exists = result.column_values(0)[0]
      result.clear

      return nil if !exists # parent thread not found
    end

    # create thread in database
    db.prepare('threads2',
      'INSERT INTO threads(author, text, ext)
      VALUES($1, $2, $3) RETURNING id')
    result = db.exec_prepared('threads2', [
      thread[:author], thread[:text], ext
    ]) # TODO check result
    id = result[0]['id']

    if reply && !parent.nil?
      # add the new thread to the parent thread's children
      db.prepare('threads3',
        'UPDATE threads
        SET children = array_append(threads.children, $1)
        WHERE threads.id = $2')

      # set the new thread's parent to be the parent thread
      db.prepare('threads4',
        'UPDATE threads
        SET parent = $1
        WHERE threads.id = $2')

      result = db.exec_prepared('threads3', [id, parent])
      result = db.exec_prepared('threads4', [parent, id])
      # TODO check result
    end

    db.close
    result.clear

    hash = hashids.encode(id)
    if !thread[:file].nil?
      f = File.open("public/file/#{hash}.#{ext}", 'w') { |i| i.write(tmp.read) }
      # TODO think about closing the temp file
    end

    return hash
  end

  def self.submit(req, user)
    if !req.post?
      return View.finalize('submit', 200, { user: user, incorrect: false })
    end

    text = req.params['text']
    file = req.params['file']
    parent = req.params['thread']
    # TODO validate each input

    if text.empty? && file.nil?
      return View.finalize('submit', 400, { user: user, incorrect: true })
    end

    hash = create_thread({
      author: user[:id],
      text: text,
      file: file,
      parent: parent
    }, !parent.nil?)

    return thread(hash, user, true) # redirect to the thread
  end

  def self.get_threads
    db = PG.connect(dbname: 'storage')
    db.prepare('threads_users',
      'SELECT threads.id, users.username AS author, threads.text, threads.ext,
      cardinality(threads.children) AS children, threads.date_created
      FROM threads
      JOIN users ON users.id = threads.author
      WHERE threads.parent IS NULL
      ORDER BY threads.date_created DESC LIMIT 20')
    result = db.exec_prepared('threads_users', []) #  TODO check result
    db.close

    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    threads = []
    result.each_row { |row|
      threads.push({
        hash: hashids.encode(row[0]),
        author: row[1],
        text: row[2],
        ext: row[3],
        children: row[4],
        date_created: date_as_sentence(row[5])
      })
    }

    result.clear
    return threads
  end

  def self.thread(hash, user, redirect = false)
    thread = get_thread(hash)
    return Router.not_found if thread.nil?

    status = 200
    headers = {}
    if redirect
      location = "/thread/#{hash}"
      headers['Location'] = location
      status = 302
    end

    return View.finalize('thread', status, {
      thread: thread, user: user
    }, headers)
  end

  # retrieve a thread and its children from its hash
  def self.get_thread(hash)
    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    id = hashids.decode(hash)[0]

    db = PG.connect(dbname: 'storage')
    db.prepare('threads_users',
      'SELECT threads.id, users.username AS author, threads.text, threads.ext,
      threads.parent, threads.children::int[], threads.date_created
      FROM threads
      JOIN users ON users.id = threads.author
      WHERE threads.id = $1 OR (
	       SELECT threads.children FROM threads
         WHERE threads.id = $1 LIMIT 1
      ) @> ARRAY[threads.id]
      ORDER BY threads.date_created LIMIT 20')
    result = db.exec_prepared('threads_users', [id]) # TODO check result
    db.close

    return nil if result.column_values(0).empty? # thread not found

    threads = []
    result.each { |row|
      threads.push({
        hash: hashids.encode(row['id']),
        author: row['author'],
        text: row['text'],
        ext: row['ext'],
        parent: row['parent'].nil? ? nil : hashids.encode(row['parent']),
        children: row['children'].tr('{}', '').split(','),
        date_created: date_as_sentence(row['date_created'])
      })
    }

    result.clear
    return threads
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
