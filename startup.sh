#start mysql in background
sudo -b /usr/local/mysql/bin/mysqld_safe

#start redis in background
redis-server redis.conf &

#start website, ctrl+c to stop test server
#(which will cause everything else to quit)
shotgun

#shutdown redis
redis-cli shutdown

#shut down mysql automatically when done
sudo /usr/local/mysql/bin/mysqladmin shutdown
