require 'bcrypt'
require 'openssl'

module Auth
  def self.login(req)
    username = req.params['username']
    password = req.params['password']
    signup = req.params['signup']
    referrer = req.referrer # TODO validate the url
    # TODO divide this part for GET and POST methods
    if username.nil? && password.nil? && signup.nil?
      return View.finalize('login')
    end

    return Users.signup(username, password) if signup
    # retrieve password from database for comparison
    rs = $db.execute('select rowid as id, password from users
                     where username = ? limit 1', [username])

    if rs.empty? # username not found
      return View.finalize('login', 200, {
        username_trial: username, invalid_username: true
      })
    end

    uid = rs[0]['id']
    password_db = rs[0]['password']
    password_hash = BCrypt::Password.new(password_db)

    if password_hash != password # passwords do not match
      return View.finalize('login', 200, {
        username_trial: username, invalid_password: true
      })
    end

    # passwords match, create session in database
    sessid = create_session(uid)

    # redirect to index
    # TODO redirect to previous page
    # first GET to /login has referrer, but then POST has referrer /login
    return Router.index(nil, true, {
      'Set-Cookie' => "sessid=#{sessid}; Path=/; HttpOnly"
    })
  end

  def self.logout(req)
    # delete session from database
    sessid = req.cookies['sessid']
    referrer = req.referrer # TODO validate referrer url

    hash = OpenSSL::Digest::SHA256.digest(sessid)
    sessid_hash = bin_to_hex(hash)

    $db.execute('delete from sessions where sessid = ?', [sessid_hash])

    res = Rack::Response.new
    res.redirect(referrer)
    return res
  end

  def self.create_session(uid)
    # create a random 16 bytes session id
    sessid = OpenSSL::Random.random_bytes(16)
    sessid_hex = bin_to_hex(sessid)
    hash = OpenSSL::Digest::SHA256.digest(sessid_hex)
    sessid_hash = bin_to_hex(hash)

    $db.execute('insert into sessions(sessid, uid) values(?, ?)',
                [sessid_hash, uid])

    return sessid_hex
  end

  def self.get_session_from_sessid(sessid)
    return if sessid.nil?
    hash = OpenSSL::Digest::SHA256.digest(sessid)
    sessid_hash = bin_to_hex(hash)

    rs = $db.execute('select users.rowid as id, users.username from users
                     join sessions on sessions.uid = users.rowid
                     where sessions.sessid = ? limit 1', [sessid_hash])

    session = nil
    if !rs.empty?
      session = {
        id: rs[0]['id'],
        username: rs[0]['username']
      }
    end

    return session
  end

  def self.hash(password)
    return BCrypt::Password.create(password, cost: 10)
  end

  def self.bin_to_hex(s)
    s.each_byte.map { |b| b.to_s(16) }.join
  end
end
