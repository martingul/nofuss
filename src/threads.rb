require 'hashids'
require 'base64'
require 'mimemagic'

module Threads
  def self.submit(req, user)
    allowed_mimes = {
      'image/jpeg' => 'jpg',
      'image/gif' => 'gif',
    }

    text = req.params['text']
    file = req.params['file']
    thread = req.params['thread']
    # TODO validate each input

    if !req.post?
      return View.finalize('submit', 200, {user: user, incorrect: false})
    end

    if text.empty? && file.nil?
      return View.finalize('submit', 400, {user: user, incorrect: true})
    end

    if !text.empty?
      # TODO verify text
    end

    if !file.nil?
      # TODO check result of disk operations
      tmp = File.open(file[:tempfile].path, 'r')

      # detect file mime and extension
      mime = MimeMagic.by_magic(tmp)
      ext = allowed_mimes["#{mime}"]
      if ext.nil?
        return View.finalize('submit', 400, {user: user, incorrect: true})
      end
    end

    # create thread in database
    conn = PG.connect(dbname: 'storage')
    conn.prepare('thread_insert',
      'INSERT INTO threads(author, text, ext)
      VALUES($1, $2, $3) RETURNING id')
    result = conn.exec_prepared('thread_insert', [user[:id], text, ext])
    # TODO check result
    id = result[0]['id']

    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    hash = hashids.encode(id)

    if !file.nil?
      f = File.open("public/file/#{hash}.#{ext}", 'w') { |i| i.write(tmp.read) }
      # TODO think about closing the temp file
    end

    return thread(hash, user, true) # redirect to the thread
  end

  def self.get_threads
    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    conn = PG.connect(dbname: 'storage')
    conn.prepare('thread_select',
      'SELECT threads.id, users.username, threads.text, threads.ext,
      cardinality(threads.children) AS children, threads.date_created
      FROM threads
      JOIN users ON users.id = threads.author
      WHERE threads.parent IS NULL
      ORDER BY threads.date_created DESC LIMIT 20')
    result = conn.exec_prepared('thread_select', []) #  TODO check result

    threads = []
    result.each_row do |row|
      threads.push({
        hash: hashids.encode(row[0]),
        author: row[1],
        text: row[2],
        ext: row[3],
        children: row[4],
        date_created: date_as_sentence(row[5])
      })
    end

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

  # retrieve a thread (and its children) from hash of thread id
  def self.get_thread(hash)
    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    id = hashids.decode(hash)[0]

    conn = PG.connect(dbname: 'storage')
    conn.prepare('thread_select',
      'SELECT threads.id, users.username, threads.text, threads.ext,
      threads.children::int[], threads.date_created
      FROM threads
      JOIN users ON users.id = threads.author
      WHERE threads.id = $1 OR (
	       SELECT threads.children FROM threads
         WHERE threads.id = $1
      ) @> ARRAY[threads.id]
      ORDER BY threads.date_created DESC LIMIT 20')
    result = conn.exec_prepared('thread_select', [id]) # TODO check result

    return nil if result.column_values(0).empty? # thread not found

    threads = []
    result.each do |row|
      threads.push({
        hash: hashids.encode(row['id']),
        author: row['author'],
        text: row['text'],
        ext: row['ext'],
        children: row['children'].tr('{}', '').split(','),
        date_created: date_as_sentence(row['date_created'])
      })
    end

    return threads
  end

  # convert a timestamp to a 'X time ago' type sentence
  def self.date_as_sentence(date)
    d = Time.parse(date)
    t_now = Time.now
    dt = t_now - d

    datetime = []
    datetime.push dt # seconds
    datetime.push dt/60 # minutes
    datetime.push dt/(60*60) # hours
    datetime.push dt/(60*60*24) # days
    datetime.push dt/(60*60*24*7) # weeks
    datetime.push dt/(60*60*24*7*52) # years

    units = { 1 => "seconds", 2 => "minutes", 3 => "hours",
      4 => "days", 5 => "weeks", 6 => "years" }

    datetime = datetime.take_while{ |i| i >= 1 }.map{ |i| i = i.truncate(0) }
    datetime.push 1 if datetime.empty? # 1 second ago
    unit = units[datetime.length] # select corresponding unit
    unit[-1] = '' if datetime[datetime.length - 1] <= 1 # check for plurality

    return "#{datetime[datetime.length - 1]} #{unit} ago"
  end
end
