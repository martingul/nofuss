module Users
  def self.signup(username, password)
    password_hash = Auth.hash(password)

    # store a new user instance and get the uid back
    seed = Random.new_seed.to_s
    $db.prepare(seed,
      'INSERT INTO users(username, password)
      VALUES($1, $2)
      RETURNING id AS uid')
    result = $db.exec_prepared(seed, [username, password_hash])
    # TODO check result
    uid = result[0]['uid']
    result.clear

    return View.finalize('login', 201, created: true, username_trial: username)
  rescue PG::Error => e
    sqlstate = e.result.error_field(PG::Result::PG_DIAG_SQLSTATE)

    if sqlstate == '23505' # unique username constraint error
      return View.finalize('login', 400, {
        username: username, username_taken: true
      })
    end
  end

  def self.get_user(username, session)
    seed = Random.new_seed.to_s
    $db.prepare(seed,
      'SELECT users.username, users.date_created
      FROM users
      WHERE users.username = $1 LIMIT 1')
    result = $db.exec_prepared(seed, [username]) # TODO check result

    return Routes.not_found if result.values.empty? # user not found

    date_created = result.column_values(1)[0]
    t_created = Time.parse(date_created).strftime("%B %e %Y")

    return View.finalize('user', 200, {
      username: username, date_created: t_created, session: session
    })
  end
end
