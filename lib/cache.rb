class Cache
  def initialize(app)
    @app = app
  end

  def printenv(env) #for debugging
    env.each { |k,v| puts "#{k}:#{v}" }
  end

  def call(env)
    client_etag   = env['HTTP_IF_NONE_MATCH']
    client_lm     = env['HTTP_IF_MODIFIED_SINCE']
    cache_control = env['HTTP_CACHE_CONTROL']
    pragma        = env['HTTP_PRAGMA']
    path          = env['REQUEST_URI']
    logged_in     = env['logged_in'] #TODO: better way to do this?

    nocache = (pragma == 'no-cache' || cache_control == 'max-age=0')
    c = nocache ? {} : $redis_cache.hgetall(path)

    if c.empty? or logged_in                 #if content not cached, or logged in
      status, headers, body = @app.call(env) #run the app
      ts = env[:timestamp]
      if ts #if the app wants to be cached
        unixtime = ts.strftime('%s').to_i
        headers['Last-Modified'] = ts.strftime('%a, %d %b %Y %H:%M:%S %z')
        headers['ETag']          = "\"#{unixtime}\""

        if not logged_in #don't cache pages if logged in
          $redis_cache.hmset(path, :time, unixtime, :body, body, :head, Marshal.dump(headers))
          $redis_cache.expire(path, 3600)
        end
      end

      [status, headers.merge!('X-Cache'=>'miss'), body]
    else
      not_modified = (client_etag == "\"#{c['time']}\"" || (client_lm && Time.parse(client_lm).to_i == c['time'].to_i))
      if not_modified
        #cache hit
        [304, {'X-Cache'=>'hit'}, []]
      else
        #client miss but content cached in Redis. Send cached content.
        [200, Marshal.load(c['head']).merge!('X-Cache'=>'server_hit'), [c['body']]]
      end
    end
  end
end