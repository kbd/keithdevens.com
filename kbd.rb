#builtins
require 'securerandom'
require 'json'

#third party
require 'cuba'
require 'redis'
require 'redis-rack'
require 'pony'

#libs
require './lib/models'
require './lib/feeds'
require './lib/forms'
require './lib/admin'

#templates
require './templates/weblog'
require './templates/weblog_archive'
require './templates/weblog_archive_year'
require './templates/weblog_archive_month'
require './templates/page'
require './templates/quote'

#constants/globals
ROOT_PATH        = File.expand_path(File.dirname(__FILE__))
ENTRIES_PER_PAGE = 100
REDIS            = 'redis://127.0.0.1:6379'
REDIS_CACHE      = "#{REDIS}/1"
REDIS_SESSION    = "#{REDIS}/2"

#create Redis globals on startup
#Redis db usage:
#db 0 - whatever
#db 1 - caching
#db 2 - sessions
#db 3 - queuing
$redis       ||= Redis.connect(url: REDIS)
$redis_cache ||= Redis.connect(url: REDIS_CACHE)

#e-mail address must be configured before the site will run
#this keeps the e-mail address from being hardcoded, and also
#keeps my e-mail address from being scraped on github :)
$EMAIL = $redis.get('mail') or raise "E-mail not configured"

CONTENT_TYPES = {
  xml:   'application/xml; charset=utf-8',
  rss:   'application/rss+xml; charset=utf-8',
  atom:  'application/atom+xml; charset=utf-8',
  xhtml: 'application/xhtml+xml; charset=utf-8',
  html:  'text/html; charset=utf-8',
  text:  'text/plain; charset=utf-8',
}

Link     = Struct.new(:name, :uri, :title)
PrevNext = Struct.new(:prev, :next) #prev and nxt should be Link objects

Cuba.use Rack::Static, urls: ["/images", "/static"], root: File.join(ROOT_PATH, "public")

Cuba.use Rack::Session::Redis,
  secret: SecureRandom.hex(64),
  redis_server: REDIS_SESSION

#quick note on paging:
#there are two "calls" that can generate an unbounded
#(well, bounded at the max number of entries) list of entries
#1. search
#2. tags
def pagetitle(page)
  "Page #{page}"
end

def paging(ds, urifunc)
  @page = req['page'].to_i
  @prevnext = PrevNext.new
  if @page > 0
    pg = pagetitle(@page)
    @title = "#{@title} (#{pg})" 
    @breadcrumbs << Link.new(pg, req.path)
    @prevnext.prev = Link.new(pagetitle(@page-1), urifunc.call(@page-1))
  end
  #to determine if there are more pages, get one more than the
  #actual number you want, and if that one more exists then there's
  #at least one more page
  items = ds.limit(ENTRIES_PER_PAGE+1, @page*ENTRIES_PER_PAGE).all
  if items.length == ENTRIES_PER_PAGE+1
    #there's at least one more entry, so show a next page
    @prevnext.next = Link.new(pagetitle(@page+1), urifunc.call(@page+1))
    #pop off the extra entry
    items.pop()
  end
  items
end

module Extensions
  def render(klass, locals={})
    #take all the instance variables and pass to the template
    #h1 = Hash[instance_variables.map { |n| [n[1..-1], instance_variable_get(n)] }]
    h = Hash[instance_variables.map { |n| [n, instance_variable_get(n)] }]
    h[:session] = session #make the session available to templates
    res.write klass.new(h.merge(locals)).to_html
  end

  def cache(items_or_date, last=false)
    t = if items_or_date.is_a? Date
      items_or_date
    else
      items_or_date[last ? -1 : 0].modification_datetime_utc if !items_or_date.empty?
    end
    env[:timestamp] = [env[:timestamp] || t, t].max if t
  end

  def not_found(str)
  res.status = 404
  res.write str
  end

  def canonical(uri)
    res.redirect uri, 301
  end  

  def found(uri)
    res.redirect uri, 302
  end
end

Cuba.plugin Extensions

Cuba.define do
  on get || post do
    #would say "on get" to start, but I accept posted comment forms only at the entry URI
    on ('.*/$') { canonical req.path.chop } #no urls may end in a slash!
    on (root) { found '/weblog' }

    on 'weblog' do
      ReversedEntries = Entry.reverse

      @breadcrumbs = [Link.new("Keith Devens", "/weblog")]
      @recent_comments = Comment.recent_by_entry.all

      #for caching, fresh will be determined by the most recent comment
      #or for the home page, or by the most recent entry, whichever is later
      cache @recent_comments
      res['Cache-Control'] = 'max-age: 3600'

      on param('search') do |search|
        @title = "Weblog search for '#{search}'";
        @breadcrumbs << Link.new("Search '#{search}'", Entry.searchuri(search))
        urifunc = lambda{ |page| Entry.searchuri(search, page) }
        @entries = paging(ReversedEntries.search(search), urifunc)
        render WeblogTemplate, search: search
      end

      on root do
        cache @entries = ReversedEntries.recent.all
        @title = 'Weblog'
        render WeblogTemplate
      end

      on '(rss|atom)' do |feed|
        res["Content-Type"] = CONTENT_TYPES[feed.to_sym]
        res.write send("weblog_#{feed}", ReversedEntries.recent.all)
      end

      on 'tags' do
        @breadcrumbs << Link.new('Tags', '/weblog/tags')

        #todo: get tag object here and use the title in the page title instead of the tag name
        on :tag do |tag|
          t = "tag '#{tag}'"
          @title = "Weblog: #{t}"
          @breadcrumbs << Link.new(t, req.path)
          urifunc = lambda{ |page| Tag.uri(tag, page) }
          cache @entries = paging(ReversedEntries.for_tags([tag]), urifunc)
          render WeblogTemplate
        end
      end

      on 'archive' do
        @breadcrumbs << Link.new("Archive", "/weblog/archive")
        on root do
          @years = Entry.years.map{ |y| [y, Entry.yearuri(y)] }
          @tags = Tag.list
          @title = 'Weblog archive'
          render WeblogArchiveTemplate
        end

        on '(\d+)' do |year|
          @year = year.to_i
          @breadcrumbs << Link.new(@year, Entry.yearuri(@year))
          on root do
            @yearentries = Hash[Entry.year(@year)]
            break not_found('no year') if @yearentries.empty?
            cache Date.new(@year, 1, 1)
            @title = "Weblog archive for #{year}"
            render WeblogArchiveYearTemplate
          end

          on '([A-Za-z0-9]+)' do |month|
            #'month' can be a string like 'Oct' or 'nov' (caps optional). Convert to the numeric month
            month = (month =~ /d+/) ? month.to_i : Date::ABBR_MONTHNAMES.index(month.capitalize) || 0
            break not_found "invalid month" if not(1 <= month and month <= 12)

            #month is now correct, show month archive
            @breadcrumbs << Link.new(Date::MONTHNAMES[month], Entry.monthuri(@year, month))
            on root do
              cache @entries = ReversedEntries.for_month(@year, month).all
              brake not_found "no entries for month" if @entries.empty?
              @title = "Weblog archive for #{Date.new(@year,month,1).strftime('%B, %Y')}"
              render WeblogArchiveMonthTemplate
            end

            on '(\d+)' do |day|
              #if we got here, a day was passed, check for validity
              day = day.to_i
              break not_found 'invalid day' if not (1 <= day and day <= 31) #todo:do a better check than this

              @breadcrumbs << Link.new("%02d" % day, Entry.dateuri(Date.new(@year, month, day)))

              on root do  # just a day's results
                be = Entry.bordering_days Date.new(@year, month, day)
                @prevnext = PrevNext.new
                @prevnext.prev = Link.new(be[0].strftime('%B %e, %Y'), Entry.dateuri(be[0])) if be[0]
                @prevnext.next = Link.new(be[1].strftime('%B %e, %Y'), Entry.dateuri(be[1])) if be[1]
                @entries = Entry.for_day(@year, month, day).all
                break not_found "No entry found for day #{day}" if @entries.empty?
                cache @entries, true
                @title = "Weblog archive for #{Date.new(@year,month,day).strftime('%B %d, %Y')}"
                render WeblogTemplate
              end

              on :slug do |slug|
                #should result in a particular entry, if found
                entry = if slug =~ /^\d+$/
                  Entry.for_id(slug.to_i)
                else #slug is a name
                  Entry.for_name(@year, month, day, slug)
                end
                break not_found "No entry for '#{slug}'" if not entry

                #if the url by which this was accessed is different from the permalink
                break canonical entry.permalink if req.path != entry.permalink
                
                ### COMMENT STUFF ###
                comment = Comment.new(entry: entry)

                #if cookie, set the values from the cookie
                cookie_fields = [:name, :email, :website]
                c = req.cookies['comment']
                if c
                  c = JSON.parse(c)
                  cookie_fields.each{ |k| comment.send("#{k}=", c[k.to_s]) } #to_s since json keys are strings
                end
                
                @comment_form = FormHelper.new('comment', comment)
                @preview_comment = nil
                if req.post?
                  if @comment_form.process(req, save: false)
                    #leave a cookie saving the user's info
                    res.set_cookie('comment',
                      value: JSON.dump(Hash[cookie_fields.map{ |k| [k, comment.send(k)] }]),
                      path: '/',
                      expires: Time.now+60*60*24*365 #year
                    )

                    #if submit, save the comment and redirect if successful
                    if @comment_form['__submit'] && @comment_form.save
                      #e-mail the comment and flush cache
                      $redis_cache.flushdb
                      Pony.mail(to: $EMAIL, subject: 'Comment on your site', body: comment.inspect)
                      break found comment.permalink
                    end

                    #otherwise, just a preview
                    @preview_comment = comment
                    @preview_comment.before_create #so it has a timestamp and such
                    #called manually beacuse you're not yet saving it so Sequel doesn't call it
                  end
                end
                ### END COMMENT STUFF ###
                    
                @breadcrumbs << Link.new(entry.title, entry.permalink)
                be = entry.bordering_entries
                @prevnext = PrevNext.new
                @prevnext.prev = Link.new(be[0].title, be[0].permalink) if be[0]
                @prevnext.next = Link.new(be[1].title, be[1].permalink) if be[1]
                cache @entries = [entry]
                @individual = true
                @title = "#{entry.title} - #{entry.creation_datetime.strftime('%B %d, %Y')}"

                render WeblogTemplate
              end
            end
          end
        end
      end

      on 'comments' do
      #   #case 'comments':$title .= ' È Recent comments'; break;
      #TODO implement this
      end

      on param('entries') do
        @title = 'Weblog (selected entries)'
        ids = req['entries'].split(',').map(&:to_i)
        @entries = Entry.for_ids(ids).all
      end

      #handle old url formats
      break canonical("/weblog/#{$1}") if req.query_string =~ /^id(\d+)$/ #in the form /weblog/?id2000
      break canonical(Entry.dateuri(Date.new($1.to_i, $2.to_i, $3.to_i))) if req.query_string =~ /^(\d{4})-(\d{2})-(\d{2})$/

      on '(\d+)' do |id|
        entry = Entry.for_id(id.to_i)
        #render(:base, content: 'Page not found')
        break not_found "Not found" unless entry
        canonical entry.permalink
      end
      
      #old rss url
      on param('rss') { canonical '/weblog/rss' }
    end

    on 'quotes' do
      @breadcrumbs = [Link.new("Keith Devens", "/"), Link.new("Quotes", '/quotes')]
      @title = "Quotes"

      on :key do |key|
        key = CGI.unescape(key)
        quote = Quote.for_key(key)
        halt not_found("No quote with that key") if not quote
        @breadcrumbs << Link.new("Quote: #{quote.title}", quote.permalink)
        @title += ": #{quote.title}"
        render QuoteTemplate, quotes: [quote]
      end

      render QuoteTemplate, quotes: Quote.all
    end

    on 'test' do
      on root do
        res.write "This is a test"
      end
      on 'session' do
        on 'clear' do
          res.write("<p>Clearing session</p>")
          session.clear
        end
        foo = session[:foo] #make sure the session is loaded
        res.write("<p>Your current session is: #{CGI.escape_html(session.inspect)}</p>")
        
        #for testing, write all querystring parameters to session vars
        req.params.each{ |q,v|
          res.write("<p>Setting session var '#{CGI.escape_html(q)}' to '#{CGI.escape_html(v)}'</p>")
          session[q] = v
        }

        res.write("<p>Your current session is: #{CGI.escape_html(session.inspect)}</p>")
      end
    end

    on 'admin' do
      run Admin
    end
    
    on default do #pages
      path = CGI.unescape(req.path)
      page = Page.for_path(path)
      break not_found("No page at #{path}") if not page or not page.visible #if not logged in
      break found(page.permalink) if path != page.permalink
      
      cache [page]
      if page.standalone
        res['Content-Type'] = CONTENT_TYPES[page.type]
        res.write page.text_html
      else
        @breadcrumbs = [Link.new("Keith Devens .com", "/"), Link.new(page.title, page.permalink)]
        res.write PageTemplate.new(
          page: page, 
          title: page.title,
          keywords: page.keywords,
          description: page.description,
          recent_pages: Page.visible.recently_changed,
          pages: Page.visible.all
        ).to_html
      end
    end
  end
end