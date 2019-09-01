module Users
  def self.signup(username, password)
    password_hash = Auth.hash(password)
    # store a new user instance and get the uid back
    $db.execute('insert into users(username, password, bio)
                values(?, ?, ?)', [username, password_hash, ''])

    return View.finalize('login', 201, created: true, username_trial: username)
    # TODO make usernames unique (handle db constraint error)
  end

  def self.get_user(username, session)
    rs = $db.execute('select users.rowid as id, users.bio, users.date_created
                     from users where users.username = ? limit 1', [username])

    return Routes.not_found if rs.empty? # user not found

    id = rs[0]['id']
    bio = rs[0]['bio']
    date_created = rs[0]['date_created']
    t_created = Time.at(date_created).strftime("%B %e %Y")

    show_deleted = false
    if !session.nil?
      show_deleted = id == session[:id]
    end

    user = { id: id, username: username, bio: bio, date_created: t_created }
    new_threads = get_history(user, 'date_created', show_deleted)
    top_threads = get_history(user, 'children', show_deleted)

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
      $db.execute('update users set bio = ? where users.rowid = ?',
                  [bio, session[:id]])
    end

    return get_user(username, session)
  end

  def self.get_history(user, sort = 'date_created', show_deleted = false)
    hashids = Hashids.new('thread', 10, 'abcdefghijklmnopqrstuvwxyz')

    stmt = 'select threads.rowid as id, threads.deleted, threads.text,
           threads.ext, threads.parent, threads.children, threads.date_created
           from threads where threads.author = ?'

    stmt += ' and not threads.deleted ' if !show_deleted

    if sort == 'date_created'
      # new threads
      stmt += 'order by threads.date_created desc limit 20'
    elsif sort == 'children'
      # top threads
      # TODO implement sort by number of children
      # stmt += 'order by cardinality(threads.children) desc limit 20'
    end

    rs = $db.execute(stmt, [user[:id]])

    threads = []
    rs.each{ |r|
      children = []
      if !r['children'].nil?
        #r['children'].split(',').map{ |c| c.to_i },
        children = []
      end

      threads.push(Render::Thread.new(
        hash: hashids.encode(r['id'].to_i),
        deleted: r['deleted'] == 1,
        author: user[:username],
        text: r['text'],
        ext: r['ext'],
        parent: r['parent'],
        children: children, 
        date_created: Threads.date_as_sentence(r['date_created'])
      ))
    }

    return threads
  end
end
