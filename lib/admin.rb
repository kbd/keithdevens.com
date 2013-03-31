require 'set'
require 'json'

require 'pony'

require './lib/models'
require './lib/forms'

require './templates/base'

class Admin < Cuba
  def logged_in #duplicates the one in BaseTemplate... DRY them somehow
    session[:logged_in]
  end

  def admin(&block)
    render BaseTemplate, content: block
  end
end

Admin.define do
  on root do
    admin do
      if logged_in
        ul {
          li {a 'Entry',  href: '/admin/Entry'}
          li {a 'Pages',  href: '/admin/Page'}
          li {a 'Quotes', href: '/admin/Quote'}
          li {a 'Tags',   href: '/admin/Tag'}
          li {a 'Logout', href: '/admin/logout'}
        }
      else
        form(method: 'POST', action: '/admin/login') {
          button "Send me a login token"
        }
      end
    end
  end

  on 'login' do
    if req.post?
      if tokenexists #protect against someone writing a script to spam me with login tokens
        admin { p "Token already sent" }
      else
        token = gettoken
        uri = env['REQUEST_URI']
        recordtoken($EMAIL, token)
        Pony.mail(to: $EMAIL, subject: 'login token', body: "#{uri}?token=#{token}")
        admin { p "Sent token" }
      end
    end

    on param('token') do
      email = matchtoken(req['token'])
      if email == $EMAIL #if token email matches admin email
        puts "Token matches, logging you in!"
        session['logged_in'] = true
        res.redirect '/admin', 302
      end
    end
  end

  on 'logout' do
    admin {p "Cleared your session"}
    session.clear
  end

  #guard admin section
  on !logged_in do
    break found '/admin'
  end

  on 'Entry' do
    entry = req['id'] ? EntryForm[req['id']] : EntryForm.new(allow_comments: true, title: '')
    form = FormHelper.new('entry', entry)

    r = req #so the request is visible within the block
    admin do
      if r.post?
        if form.process(r)
          h3.success "Successfully saved"
        end
      end

      form.form { |f|
        display_form_errors form
        table.entry_form {
          tr {
            td { f.label :title, 'Title' }
            td { f.text :title, style: 'width: 70%' }
          }
          tr {
            td { f.label :name, 'Name' }
            td { f.text :name, style: 'width: 35%' }
          }
          tr {
            td(colspan: 2){
              f.label :text, 'Entry text'; br
              f.textarea :text, rows: 20, cols: 80
            }
          }
          tr {
            td(colspan: 2){
              f.label :tag_str, 'Tags'; br
              f.textarea :tag_str, rows: 2, cols: 80
            }
          }
          tr {
            td(colspan: 2) {
              f.checkbox :update_modified; text nbsp
              f.label :update_modified, 'Update modified datetime'
            }
          }
          tr {
            td(colspan: 2) {
              f.checkbox :allow_comments; text nbsp
              f.label :allow_comments, 'Allow comments'
            }
          }
          tr {
            td(colspan: 2){ f.submit "Save entry" }
          }
        }
      }
      script(language: 'javascript', type: 'text/javascript', src: '/static/actb/common.js')
      script(language: 'javascript', type: 'text/javascript', src: '/static/actb/actb.js')
      javascript("
        a = actb(document.getElementById('#{form.field_id(:tag_str)}'), #{Tag.all_names.to_json});
        a.actb_delimiter = [' ']; a.actb_lim = 5; a.actb_firstText = true;
      ")
    end
  end
end

class EntryForm < Entry
  attr_accessor :update_modified

  whitelist :update_modified, :tag_str

  def after_initialize(*args)
    super
    @update_modified = true
  end

  def tag_str
    tags.map(&:name).join(' ')
  end

  def tag_str=(s)
    s = s.split #split the tag string on space
    existing = Tag.for_names(s).all #get all the existing tags

    #create tags for tag names that don't exist
    lc_existing = existing.map{|t|t.name.downcase}.to_set
    new = s.select{ |t| !lc_existing.include? t.downcase }
    existing.concat(new.map{ |name| Tag.create(name: name) })

    tags = existing
  end

  def title
    self[:title] #the base Entry model makes up a title if title is null
  end

  def before_save #Sequel method
    puts "Updated modified is '#{@update_modified}'. Saving if true"
    self.modification_datetime = DateTime.now if @update_modified
    super
  end
end

def gettoken
  Digest::SHA2.new.update(Time.now.to_s)
end

def recordtoken(email, token)
  key = "token:#{token}"
  $redis.multi do
    $redis.hmset(key, 'mail', email, 'ip', req.ip)
    $redis.expire(key, 300)
  end
end

def tokenexists()
  #this just checks if any token has been sent
  #this won't account for multiple logins, improve later
  !$redis.keys('token:*').empty?
end

def matchtoken(token)
  redistoken = $redis.multi do
    $redis.hgetall("token:#{token}")
    $redis.del("token:#{token}")
  end[0]
  puts redistoken.inspect
  if redistoken && !redistoken.empty? #requested token matched
    raise "Token ip didn't match request ip" if redistoken['ip'] != req.ip
    redistoken['mail']
  end
end

# on 'login' do
#   puts "GOT TO login. Req is:"
#   require 'CGI'
#   puts CGI.unescape(req.query_string).gsub('&',"\n")
#   session['logged_in'] = true
#   found('/admin')
# end

# uri = 'https://www.google.com/accounts/o8/id'
# uri = 'https://www.google.com/accounts/o8/ud'
# settings = {
#   #required parameters
#   'openid.mode' => 'checkid_setup',
#   'openid.ns' => 'http://specs.openid.net/auth/2.0',
#   'openid.return_to' => 'http://localhost:9393/admin/login',

#   #spec says these are optional but it doesn't work without them
#   'openid.claimed_id' => 'http://specs.openid.net/auth/2.0/identifier_select',
#   'openid.identity' => 'http://specs.openid.net/auth/2.0/identifier_select',
#   # 'openid.realm' => 'http://localhost:9393/',

#   #show favicon on approval page
#   'openid.ns.ui' => 'http://specs.openid.net/extensions/ui/1.0',
#   'openid.ui.icon' => 'true',

#   #get e-mail address to verify
#   'openid.ns.ax' => 'http://openid.net/srv/ax/1.0',
#   'openid.ax.mode' => 'fetch_request',
#   'openid.ax.required' => 'email',
#   'openid.ax.type.email' => 'http://schema.openid.net/contact/email',
# }
# uri += '?'+URI.encode_www_form(settings) 

# if !session['logged_in']
#   puts "NOT LOGGED IN, REDIRECTING"
#   found(uri)
# else
#   puts "I'm logged in!"
# end
