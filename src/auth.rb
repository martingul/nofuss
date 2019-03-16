require 'bcrypt'
require 'openssl'

module Auth
  def self.login(req)
    username = req.params['username']
    password = req.params['password']
    signup = req.params['signup']
    # TODO validate username and password
    # TODO divide this part for GET and POST methods
    if username.nil? && password.nil? && signup.nil?
      return View.finalize('login')
    end

    return Users.signup(username, password) if signup
    # retrieve password from database for comparison
    seed = Random.new_seed.to_s
    $db.prepare(seed,
      'SELECT id, password
      FROM users
      WHERE username = $1 LIMIT 1')
    result = $db.exec_prepared(seed, [username]) # TODO check result

    if result.values.empty? # username not found
      return View.finalize('login', 200, {
        username_trial: username, invalid_username: true
      })
    end

    uid = result.column_values(0)[0]
    password_db = result.column_values(1)[0]
    result.clear
    password_hash = BCrypt::Password.new(password_db)

    if password_hash != password # passwords do not match
      return View.finalize('login', 200, {
        username_trial: username, invalid_password: true
      })
    end

    # passwords match, create session in database
    sessid = create_session(uid)

    # redirect to index
    return Router.index(nil, true, {
      'Set-Cookie' => "sessid=#{sessid}; Path=/; HttpOnly"
    })
  end

  def self.logout(req)
    # delete session from database
    sessid = req.cookies['sessid']

    hash = OpenSSL::Digest::SHA256.digest(sessid)
    sessid_hash = bin_to_hex(hash)

    seed = Random.new_seed.to_s
    $db.prepare(seed, 'DELETE FROM sessions WHERE sessid = $1')
    result = $db.exec_prepared(seed, [sessid_hash])
    result.clear # TODO check result

    # redirect to index
    return Router.index(nil, true)
  end

  def self.create_session(uid)
    # create a random 16 bytes session id
    sessid = OpenSSL::Random.random_bytes(16)
    sessid_hex = bin_to_hex(sessid)
    hash = OpenSSL::Digest::SHA256.digest(sessid_hex)
    sessid_hash = bin_to_hex(hash)

    seed = Random.new_seed.to_s
    $db.prepare(seed,
      'INSERT INTO sessions(sessid, uid)
      VALUES($1, $2)')
    result = $db.exec_prepared(seed, [sessid_hash, uid])
    result.clear # TODO check result

    return sessid_hex
  end

  def self.get_session_from_sessid(sessid)
    return if sessid.nil?
    hash = OpenSSL::Digest::SHA256.digest(sessid)
    sessid_hash = bin_to_hex(hash)

    seed = Random.new_seed.to_s
    $db.prepare(seed,
      'SELECT users.id, users.username
      FROM users
      JOIN sessions ON sessions.uid = users.id
      WHERE sessions.sessid = $1 LIMIT 1')
    result = $db.exec_prepared(seed, [sessid_hash])
    # TODO check result

    if !result.values.empty?
      session = {
        id: result.column_values(0)[0],
        username: result.column_values(1)[0]
      }
    else
      session = nil
    end

    result.clear
    return session
  end

  def self.hash(password)
    return BCrypt::Password.create(password, cost: 10)
  end

  def self.bin_to_hex(s)
    s.each_byte.map { |b| b.to_s(16) }.join
  end
end
