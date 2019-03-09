require './src/auth.rb'
require './src/users.rb'
require './src/threads.rb'

module Router
  def self.route(req, env = {})
    # TODO check method
    sessid = req.cookies['sessid'] # TODO validate sessid cookie
    user = Auth.get_user_from_sessid(sessid)

    query = Rack::Utils.parse_query(req.path, '/').keys
    case query[0]
    when nil
      return index(req, 200, {}, user)
    when 'login'
      if user[:id].nil?
        return Auth.login(req, user)
      else
        return index(req, 302, {'Location' => '/'}, user)
      end
    when 'logout'
      return Auth.logout(req)
    when 'user'
      return query[1].nil? ? not_found : Users.get_user(req, query[1], user)
    when 'submit'
      if user[:id].nil?
        return index(req, 302, {'Location' => '/'}, user)
      else
        return Threads.submit(req, user)
      end
    when 'thread'
      return query[1].nil? ? not_found : Threads.thread(query[1], user)
    else
      return not_found
    end
  end

  def self.index(req, status = 200, headers = {}, user = {})
    threads = Threads.get_threads # retrieve index page threads

    return View.finalize('index', status, {
      user: user.nil? ? {} : user,
      threads: threads
    }, headers)
  end

  def self.not_found
    body = ['404 Not found']
    return Rack::Response.new(body, 200, {"Content-Type" => "text/plain"})
  end
end
