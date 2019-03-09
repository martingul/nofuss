module Users
  def self.signup(username, password, user)
    password_hash = Auth.hash(password)

    # store a new user instance and get the uid back
    db = PG.connect(dbname: 'storage')
    db.prepare('users',
      'INSERT INTO users(username, password)
      VALUES($1, $2)
      RETURNING id AS uid')
    result = db.exec_prepared('users', [username, password_hash])
    # TODO check result
    uid = result[0]['uid']

    db.close
    result.clear

    sessid = Auth.create_session(uid)

    return View.finalize('index', 302, { username: username, user: user }, {
      'Set-Cookie' => "sessid=#{sessid}; Path=/; HttpOnly",
      'Location' => '/'
    })
  rescue PG::Error => e
    sqlstate = e.result.error_field(PG::Result::PG_DIAG_SQLSTATE)

    if sqlstate == '23505' # unique username constraint error
      return View.finalize('login', 400, {
        username: username, username_taken: true, user: user
      })
    end
  end

  def self.get_user(req, username, user)
    # XXX req not needed
    # TODO validate username
    db = PG.connect(dbname: 'storage')
    db.prepare('user_select',
      'SELECT users.username, users.date_created
      FROM users
      WHERE users.username = $1 LIMIT 1')
    result = db.exec_prepared('user_select', [username]) # TODO check result
    # username not found in database
    return Routes.not_found if result.values.empty?

    date_created = result.column_values(1)[0]
    t_created = Time.parse(date_created).strftime("%B %e %Y")

    return View.finalize('user', 200, {
      username: username, date_created: t_created, user: user
    })
  end
end
