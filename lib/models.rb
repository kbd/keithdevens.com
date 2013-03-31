require 'cgi'
require 'set'
require 'logger'
require 'digest/md5'
require 'date' #for Time.to_datetime (Ruby monkeypatching like this is retarded)

require 'sequel'

require_relative 'markdown' #gets 'Markdown'

RECENT_DAYS = 5
connstr = 'mysql2://root@localhost/keithd_staging?charset=UTF8'
Sequel.datetime_class = DateTime #ignored by mysql2 driver apparently, which returns Time
Sequel.default_timezone = :utc

DB = Sequel.connect(connstr)
DB.logger = Logger.new($stdout)
#DB.sql_log_level = :debug

class Sequel::Model
  alias :id :pk #I never use an 'id' field but like to refer to the primary key as 'id' in code.

  class << self
    def whitelist *symbols
      @whitelist ||= Set.new
      symbols.empty? ? @whitelist : @whitelist.merge(symbols)
    end
    def inherited subclass
      subclass.whitelist *whitelist if !whitelist.empty?
      super
    end
  end
  def whitelist
    self.class.whitelist
  end
end

def alt_if_blank(value, alt)
  value.nil? || value.empty? ? alt : value
end

def localize_datetime(utc, local)
  #Return datetime with correct time zone based on the difference between utc and local
  utc, local = utc.to_datetime, local.to_datetime #both will have time zone of utc
  utc.new_offset(local - utc) #subtract to get the time zone offset
end

class Tag < Sequel::Model
  many_to_many :entries,  join_table: :Entry_Tags
  many_to_many :children, join_table: :Tag_Tags, left_key: :tag_id_parent, right_key: :tag_id_child,  class: self 
  many_to_many :parents,  join_table: :Tag_Tags, left_key: :tag_id_child,  right_key: :tag_id_parent, class: self
  
  set_dataset order(:title)

  def_dataset_method(:list){ order(:title) }
  def_dataset_method(:for_name){ |name| filter(name: name) } #case insensitive in mysql! (which is what I want)
  def_dataset_method(:for_names){ |names| for_name(names) }
  def_dataset_method(:all_names){ select_order_map(:name) }
  #def_dataset_method(:all_names_by_freq){  } to implement
  
  def uri; self.class.uri(name) end
  def self.uri(name, page=0)
    p = (page == 0) ? '' : "?page=#{page}"
    "/weblog/tags/#{CGI.escape(name)}#{p}"
  end

  def before_create
    self[:title] ||= name.gsub('-',' ').split.map(&:capitalize).join(' ')
    super
  end

  def weight; 4 end
end

class Entry < Sequel::Model
  one_to_many :comments, reciprocal: :entry
  many_to_many :tags, join_table: :Entry_Tags, graph_join_type: :inner

  set_dataset order(:creation_datetime_utc)

  whitelist :title, :name, :text, :allow_comments

  def creation_datetime;          localize_datetime(self[:creation_datetime_utc],     self[:creation_datetime]) end
  def modification_datetime;      localize_datetime(self[:modification_datetime_utc], self[:modification_datetime]) end
  def creation_datetime=(dt);     self[:creation_datetime_utc],     self[:creation_datetime]     = dt, (dt + dt.offset) end
  def modification_datetime=(dt); self[:modification_datetime_utc], self[:modification_datetime] = dt, (dt + dt.offset) end
  def creation_datetime_utc;      self[:creation_datetime_utc].to_datetime end
  def modification_datetime_utc;  self[:modification_datetime_utc].to_datetime end
  #There's no need for 'creation_datetime_utc=' etc. because you *need* to assign
  #with a local version so you have the local offset available
  
  #type = Field(Enum('structuredtext','html','markdown'), colname='Type', required=True)
  #precedence = Field(Integer, colname='Precedence')
  
  def_dataset_method(:for_id){ |id| self[id] }
  def_dataset_method(:for_ids){ |*ids| filter(entry_id: ids).eager(:comments) }
  
  def_dataset_method(:for_name){ |year, month, day, name|
    for_day(year, month, day).first(name: name)
  }
  
  def_dataset_method(:for_year){ |year|
    y = Date.new(year,1,1)
    for_date_range(y, y.next_year)
  }
  
  def_dataset_method(:for_month){ |year, month|
    m = Date.new(year, month, 1)
    for_date_range(m, m >> 1).reverse
  }
  
  def_dataset_method(:for_day){ |year, month, day|
    for_date(Date.new(year, month, day))
  }
  
  def_dataset_method(:for_date){ |date|
    for_date_range(date, date+1).eager(:comments)
  }
  
  def_dataset_method(:for_date_range){ |from, to|
    filter(creation_datetime: from...to).eager(:tags)
  }
  
  def_dataset_method(:for_tags){ |tag_names|
    eager_graph(:tags).where(tags__name: tag_names)
  }

  def_dataset_method(:search){ |string|
    words = string.split.uniq.select{|w| w.length > 1}
    return nil if words.empty?
    words.reduce(self){ |f,w|
      w = "%#{w}%"
      f.filter(:title.ilike(w)).or(:text.ilike(w)) #todo: add tags
    }.eager(:tags, :comments)
  }

  def_dataset_method(:recent){ |numdays=RECENT_DAYS|
    #Return a list of the past 'numdays' worth of entries where there is an entry on each of those days
    days = Entry.recent_days(numdays)
    filter(days.map{ |d| {creation_datetime: d...d+1} }.reduce(:|)).eager(:tags,:comments)
  }

  def bordering_entries
    c, id = creation_datetime_utc, entry_id
    ds = self.class.order(:entry_id)
    [ds.reverse.first{(creation_datetime_utc <= c) & (entry_id < id)}, ds.first{(creation_datetime_utc >= c) & (entry_id > id)}]
  end
  
  def self.bordering_days(date)
    d = date.to_date #make sure it's a date and not a datetime
    q = Entry.select{DATE(creation_datetime)}.limit(1)
    before = q.filter{creation_datetime <  d  }.order{creation_datetime.desc}
    after  = q.filter{creation_datetime >= d+1}.order{creation_datetime.asc}
    before.union(after, from_self: false).select_map #should this be map or select_map?
  end

  def self.year(year)
    #Return list of tuples of (date, count) for a whole year
    group_and_count{DATE(creation_datetime).as(:date)}.for_year(year).map([:date,:count])
  end

  def self.years
    #Return a list of years that have weblog entries
    group{YEAR(creation_datetime)}.select_order_map{YEAR(creation_datetime)}
  end

  def self.recent_days(numdays=RECENT_DAYS, enddate=nil)
    #Get a list of the past $limit days that have entries
    d = (enddate or DateTime.now.new_offset)
    select{DATE(creation_datetime).as(days)}.filter{creation_datetime < d}.reverse.limit(numdays).map(:days)
  end

  def title; alt_if_blank(self[:title], "Entry #{id}") end
  def comment_count; comments.length end
  
  ### URI GETTERS ###
  def slug; name or id.to_s end
  def permalink; "#{dateuri}/#{CGI.escape(slug)}"end
  
  def dateuri; self.class.dateuri(creation_datetime) end
  def self.dateuri(date) "/weblog/archive/#{date.strftime('%Y/%b/%d')}" end

  def monthuri; self.class.monthuri(creation_datetime.year, creation_datetime.month) end
  def self.monthuri(year, month) "#{yearuri(year)}/#{Date::ABBR_MONTHNAMES[month]}" end
  
  def yearuri; self.class.yearuri(creation_datetime.year) end
  def self.yearuri(year) "/weblog/archive/#{year}" end

  def self.searchuri(search, page=0)
    p = (page == 0) ? '' : "&page=#{page}"
    "/weblog?search=#{CGI.escape(search)}#{p}"
  end
  ## END URI GETTERS ###

  def text=(text)
    raise "Text cannot be blank" if text.empty?
    self.type = 'markdown'
    self.text_html = Markdown.render(text)
    super
  end

  def before_create #Sequel method
    self.creation_datetime = DateTime.now
    self.modification_datetime = DateTime.now
    super
  end
end

class Comment < Sequel::Model
  many_to_one :entry

  set_dataset eager(:entry)
  
  whitelist :name, :email, :website, :text
  
  def gravatar_image
    hash = Digest::MD5.hexdigest(email.downcase)
    "<img class=\"gravatar\" src=\"http://www.gravatar.com/avatar/#{hash}?d=identicon&s=32\" />"
  end
  
  def_dataset_method(:recent_filter){ |numdays=RECENT_DAYS|
    filter{(creation_datetime_utc >= (DateTime.now - numdays)) & {flag: nil}}
  }

  def_dataset_method(:recent_tail){ |query|
    query.order(:creation_datetime.desc).filter(flag: nil)
  }
  
  def_dataset_method(:recent){ |numdays=RECENT_DAYS|
    recent_tail(recent_filter)
  }

  def_dataset_method(:recent_by_entry){ |numdays=RECENT_DAYS|
    recent_tail(
      join(recent_filter.select{[entry_id, MAX(creation_datetime).as(creation_datetime)]}
        .group(:entry_id), [:entry_id, :creation_datetime])
    )
  }

  def creation_datetime; self[:creation_datetime].to_datetime end
  def creation_datetime_utc;
    self[:creation_datetime_utc] ? self[:creation_datetime_utc].to_datetime : creation_datetime 
  end

  def permalink; "#{entry.permalink}#comment#{id}" end
  def name; alt_if_blank(self[:name], ip_address) end

  def title(len=10)
    t = text[/(?:\s*\S+){0,#{len}}/]
    t.length < text.length ? t + '...' : t
  end

  def before_create #Sequel method
    self.creation_datetime ||= DateTime.now
    super
  end

  def text=(text)
    raise "Comment text cannot be blank" if text.empty?
    self.text_html = Markdown.render(text)
    super
  end
end

class Page < Sequel::Model
  alias :permalink :path
  
  set_dataset order(:title)
  
  #property flag = Field(Enum('moved','deleted'), colname='Flag')

  def_dataset_method(:visible){ filter(flag: nil, public: 1) }
  def_dataset_method(:for_path){ |path| first(path: path) }
  def_dataset_method(:recently_changed){ |days=5|
    filter{modification_datetime_utc > DateTime.now - days}
      .order(:modification_datetime_utc.desc)
  }

  def visible; flag == nil && self.public end
end

class Quote < Sequel::Model
  set_dataset order(:creation_datetime.asc, :quote_id)
  
  def_dataset_method(:for_key){ |key| first(Key: key) }
  def_dataset_method(:random){ order('RAND()'.lit).first }

  def title(len=5)
    t = text[/(?:\s*\S+){0,#{len}}/] #get first len "words"
    t.length < text.length ? t + '...' : t
  end
  
  def permalink; "/quotes/#{CGI.escape(key)}" end
end
