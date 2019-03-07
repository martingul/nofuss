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
    result = conn.exec_prepared('thread_insert',
      [user[:id], text, ext])
    # TODO check result
    id = result[0]['id']

    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    hash = hashids.encode(id)

    if !file.nil?
      f = File.open("assets/f/#{hash}.#{ext}", 'w') { |i| i.write(tmp.read) }
      # TODO think about closing the temp file
    end

    # redirect to the thread
    return get_thread(req, hash, user, true)
  end

  def self.get_threads()
    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    conn = PG.connect(dbname: 'storage')
    conn.prepare('thread_select',
      'SELECT users.username, threads.id, threads.text,
      threads.ext, threads.date_created FROM threads
      JOIN users ON users.id = threads.author
      ORDER BY threads.date_created DESC LIMIT 20')
    result = conn.exec_prepared('thread_select', [])
    #  TODO check result

    threads = []
    result.each_row do |row|
      thread = {}
      thread[:author] = row[0]
      thread[:hash] = hashids.encode(row[1])
      thread[:text] = row[2]
      thread[:ext] = row[3]
      thread[:date_created] = to_sentence(row[4])
      threads.push(thread)
    end

    return threads
  end

  def self.get_thread(req, hash, user, redirect = false)
    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    id = hashids.decode(hash)[0]

    conn = PG.connect(dbname: 'storage')
    conn.prepare('thread_select',
      'SELECT users.username, threads.text, threads.ext, threads.date_created
      FROM threads JOIN users ON users.id = threads.author
      WHERE threads.id = $1 LIMIT 1')
    result = conn.exec_prepared('thread_select', [id])
    # TODO check result
    # thread not found in database
    return Router.not_found(req) if result.column_values(0).empty?

    author = result.column_values(0)[0]
    text = result.column_values(1)[0]
    ext = result.column_values(2)[0]
    date_created = to_sentence(result.column_values(3)[0])

    thread = {
      author: author, text: text, ext: ext, hash: hash,
      date_created: date_created,
    }

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

  def self.to_sentence(date)
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
