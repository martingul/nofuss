module Users
  def self.signup(username, password)
    password_hash = Auth.hash(password)
    # store a new user instance and get the uid back
    seed = Random.new_seed.to_s
    $db.prepare(seed,
      'INSERT INTO users(username, password, bio)
      VALUES($1, $2, \'\')')
    result = $db.exec_prepared(seed, [username, password_hash])
    result.clear

    return View.finalize('login', 201, created: true, username_trial: username)
  rescue PG::Error => e
    puts e.inspect
    puts e.backtrace.join("\n")
    
    sqlstate = e.result.error_field(PG::Result::PG_DIAG_SQLSTATE)

    if sqlstate == '23505' # unique username constraint error
      return View.finalize('login', 400, username_taken: true)
    end
  end

  def self.get_user(username, session)
    seed = Random.new_seed.to_s
    $db.prepare(seed,
      'SELECT users.id, users.bio, users.date_created
      FROM users
      WHERE users.username = $1 LIMIT 1')
    result = $db.exec_prepared(seed, [username])

    return Routes.not_found if result.values.empty? # user not found

    id = result.column_values(0)[0]
    bio = result.column_values(1)[0]
    date_created = result.column_values(2)[0]
    result.clear
    t_created = Time.parse(date_created).strftime("%B %e %Y")

    exclude_deleted = id != session[:id]
    user = { id: id, username: username, bio: bio, date_created: t_created }
    new_threads = get_history(user, 'date_created', exclude_deleted)
    top_threads = get_history(user, 'children', exclude_deleted)

    return View.finalize('user', 200, {
      user: user,
      new_threads: new_threads,
      top_threads: top_threads,
      session: session
    })
  end

  def self.edit_user(req, username, session)
    return if session[:username] != username # not authorized
    bio = req.params['bio']

    if !bio.nil?
      seed = Random.new_seed.to_s
      $db.prepare(seed,
      'UPDATE users
      SET bio = $1
      WHERE users.id = $2')

      result = $db.exec_prepared(seed, [bio, session[:id]])
      result.clear
    end

    return get_user(username, session)
  end

  def self.get_history(user, sort = 'date_created', exclude_deleted = false)
    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')
    seed = Random.new_seed.to_s

    statement = 'SELECT threads.id, threads.deleted, threads.text, threads.ext,
      threads.parent, threads.children::int[], threads.date_created
      FROM threads
      WHERE threads.author = $1'

    statement += ' AND NOT threads.deleted ' if exclude_deleted

    if sort == 'date_created'
      # new threads
      statement += 'ORDER BY threads.date_created DESC LIMIT 20'
    elsif sort == 'children'
      # top threads
      statement += 'ORDER BY cardinality(threads.children) DESC LIMIT 20'
    end

    $db.prepare(seed, statement)
    result = $db.exec_prepared(seed, [user[:id]])

    threads = []
    result.each_row { |row|
      threads.push(Render::Thread.new(
        hash: hashids.encode(row[0].to_i),
        deleted: row[1] == 't',
        author: user[:username],
        text: row[2],
        ext: row[3],
        parent: row[4],
        children: row[5].tr('{}', '').split(',').map{ |c| c.to_i },
        date_created: Threads.date_as_sentence(row[6])
      ))
    }

    return threads
  end
end
