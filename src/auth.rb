require 'bcrypt'
require 'openssl'

module Auth
  def self.login(req, user = {})
    username = req.params['username']
    password = req.params['password']
    signup = req.params['signup']
    # TODO divide this part for GET and POST methods
    if username.nil? && password.nil? && signup.nil?
      return View.finalize('login', 200, user: user)
    end

    # TODO validate username and password

    return Users.signup(username, password, user) if signup

    # retrieve password from database from comparison
    db = PG.connect(dbname: 'storage')
    db.prepare('users',
      'SELECT id, password
      FROM users
      WHERE username = $1 LIMIT 1')
    result = db.exec_prepared('users', [username]) # TODO check result
    db.close

    if result.values.empty?
      # username not found
      return View.finalize('login', 200, {
        username_trial: username, invalid_username: true, user: user
      })
    end

    uid = result.column_values(0)[0]
    password_db = result.column_values(1)[0]
    result.clear
    password_hash = BCrypt::Password.new(password_db)

    if password_hash != password
      # passwords do not match
      return View.finalize('login', 200, {
        username_trial: username, invalid_password: true, user: user
      })
    end

    # passwords match, create session in database
    sessid = create_session(uid)

    # redirect to index
    return Router.index(req, 302, {
      'Set-Cookie' => "sessid=#{sessid}; Path=/; HttpOnly",
      'Location' => '/'
    })
  end

  def self.logout(req)
    # delete session from database
    sessid = req.cookies['sessid']

    hash = OpenSSL::Digest::SHA256.digest(sessid)
    sessid_hash = bin_to_hex(hash)

    db = PG.connect(dbname: 'storage')
    db.prepare('sessions', 'DELETE FROM sessions WHERE sessid = $1')
    result = db.exec_prepared('sessions', [sessid_hash])
    # TODO check result
    db.close
    result.clear

    # redirect to index
    return Router.index(req, 302, {
      'Location' => '/'
    })
  end

  def self.create_session(uid)
    # create a random 16 bytes session id
    sessid = OpenSSL::Random.random_bytes(16)
    sessid_hex = bin_to_hex(sessid)
    hash = OpenSSL::Digest::SHA256.digest(sessid_hex)
    sessid_hash = bin_to_hex(hash)

    db = PG.connect(dbname: 'storage')
    db.prepare('sessions',
      'INSERT INTO sessions(sessid, uid)
      VALUES($1, $2)')
    result = db.exec_prepared('sessions', [sessid_hash, uid])
    # TODO check result
    db.close
    result.clear

    return sessid_hex
  end

  def self.get_user_from_sessid(sessid)
    return { id: nil, username: nil } if sessid.nil?
    hash = OpenSSL::Digest::SHA256.digest(sessid)
    sessid_hash = bin_to_hex(hash)

    db = PG.connect(dbname: 'storage')
    db.prepare('users_sessions',
      'SELECT users.id, users.username
      FROM users
      JOIN sessions ON sessions.uid = users.id
      WHERE sessions.sessid = $1 LIMIT 1')
    result = db.exec_prepared('users_sessions', [sessid_hash])
    # TODO check result
    db.close

    id = nil
    username = nil
    if !result.values.empty?
      id = result.column_values(0)[0]
      username = result.column_values(1)[0]
    end

    result.clear
    return { id: id, username: username }
  end

  def self.hash(password)
    return BCrypt::Password.create(password, cost: 10)
  end

  def self.bin_to_hex(s)
    s.each_byte.map { |b| b.to_s(16) }.join
  end
end
