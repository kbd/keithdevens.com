require 'nokogiri'

$DOMAIN = 'keithdevens.com'
$WEBLOG_NAME = "Keith's Weblog"
$WEBLOG_ADDRESS = "http://#{$DOMAIN}/weblog"

def rss(channelparams={}, ns={})
	params = ns.update :version => '2.0'
	
	builder = Nokogiri::XML::Builder.new do |xml|
		xml.rss params do |rss|
			rss.channel do |c|
				c.language 'en-us'
				c.image do |i|
					i.link "#{$WEBLOG_ADDRESS}"
					i.title 'Keith Devens .com'
					i.url "http://#{$DOMAIN}/images/kbd.gif"
				end
				#fill in channel params here
			end
			rss.items{ |items| yield items if block_given? }
		end
	end
	builder.to_xml

	#get last modification time
	#weblog_sendFeed('rss', $time, $xml);
end

def rss_entries(channel, entries)
	rss(channel, 'xmlns:wfw'=>'http://wellformedweb.org/CommentAPI/') do |items|
		entries.map do |e|
			next if e.tags.find{ |tag| tag.name == 'hidden' }
			
			items.item do |i|
				i.title           e.title
				i.link            "http://#{$DOMAIN}#{e.permalink}"
				i.guid            "http://www.keithdevens.com/weblog/#{e.id}"
				i.comments        "#{e.permalink}#comments"
				i['wfw'].commentRSS "#{e.permalink}/rss", :isPermaLink=>'false'
				i.pubDate         e.creation_datetime
				i.description     e.text_html, :enable_abs_links => 'true'
				e.tags.each{ |t| i.category t.title }
			end
		end
	end
end

def rss_comments(channel, comments, titleproc)
	rss(channel) do |items|
		comments.each do |c|
			#$entry = g($c, array('entry_name'=>'name','entry_id'=>'id','entry_creation_datetime'=>'creation_datetime'));
			items.item do |i|
				i.title       titleproc.call("by #{c.name}")
				i.link        "http://#{$DOMAIN}#{e.permalink}#comment#{c.id}"
				i.guid        "#{$WEBLOG_ADDRESS}/#{c.entry.id}#comment#{c.id}", :isPermaLink=>'false'
				i.pubDate     c.creation_datetime
				i.description c.text_html, :enable_abs_links => 'true'
			end
		end
	end
end

def weblog_rss(entries)
	channel = {
		:title       => $WEBLOG_NAME,
		:link        => $WEBLOG_ADDRESS,
		:description => 'The weblog of Keith Devens',
		:time        => '' #weblog_get_last_modification_time($entries)
	}
	rss_entries(channel, entries)
end

def weblog_category_rss(entries, tag)
	channel = {
		:title       => "#{$WEBLOG_NAME} (tag \"#{tag.title}\")",
		:link        => "http://#{$DOMAIN}#{tag.url}",
		:description => "The weblog of Keith Devens, tag \"#{$tag.title}\"",
		:time        => ''#weblog_get_last_modification_time($entries)
	}
	rss_entries(channel, entries)
end

def weblog_comments_rss(entry, comments)
	#weblog_munge_comment_timestamps($comments);
	channel = {
		:title       => "#{$WEBLOG_NAME}: Comments on \"#{entry.title}\"",
		:description => "#{$WEBLOG_NAME}: Comments on \"#{entry.title}\", posted on #{entry.creation_datetime.strftime('%B %e, %Y')}",
		:link        => "http://#{$DOMAIN}#{e.permalink}",
		:time        => ''#$comments ? weblog_get_last_modification_time($comments) : $entry['modification_timestamp']
	}

	#screw categories for a comments rss?
	#e.tags.each{ |t| i.category t.title }
	#if($entry['categories'])
	#	$channel['category'] = pickfield('Title', $entry['categories']);

	rss_comments(channel, comments, Proc.new{ |t| t })
end

def weblog_recent_comments_rss(comments)
	#weblog_munge_comment_timestamps($comments);
	channel = {
		:title       => "#{$WEBLOG_NAME} &raquo; Recent comments",
		:description => "Recent comments on #{$WEBLOG_NAME}",
		:link        => "#{$WEBLOG_ADDRESS}/comments",
		:time        => ''#weblog_get_last_modification_time($comments)
	}
	rss_comments(channel, comments, Proc.new{ |t| "Comments on '#{i.entry.title}" })
end

#function weblog_munge_comment_timestamps(&$comments){
#	array_walk($comments, create_function('&$a','$a[\'modification_timestamp\'] = $a[\'creation_timestamp\'] = getGmt($a[\'creation_datetime\']);')); #comments don't have a modification time, but the RSS generator expects it
#}

def rss_entries(channel, entries)
	rss(channel, 'xmlns:wfw'=>'http://wellformedweb.org/CommentAPI/') do |items|
		entries.map do |e|
			next if e.tags.find{ |tag| tag.name == 'hidden' }
			
			items.item do |i|
				i.title           e.title
				i.link            "http://#{$DOMAIN}#{e.permalink}"
				i.guid            "http://www.keithdevens.com/weblog/#{e.id}"
				i.comments        "#{e.permalink}#comments"
				i['wfw'].commentRSS "#{e.permalink}/rss", :isPermaLink=>'false'
				i.pubDate         e.creation_datetime
				i.description     e.text_html, :enable_abs_links => 'true'
				e.tags.each{ |t| i.category t.title }
			end
		end
	end
end

def weblog_atom(entries)
	root = "http://#{$DOMAIN}/"
	#time = weblog_get_last_modification_time($entries);
	builder = Nokogiri::XML::Builder.new do |xml|
		xml.feed(
			:xmlns => 'http://www.w3.org/2005/Atom',
			'xml:lang' => 'en-us',
			'xml:base' => root
		) do |feed|
			feed.id_      $WEBLOG_ADDRESS
			feed.title    $WEBLOG_NAME
			feed.updated  DateTime.now.to_s #todo: change this to the actual time
			feed.link(:rel => 'self', :href => '/weblog/atom')
			feed.link(:href => '/weblog')
			
			feed.author{ |a| a.name 'Keith Devens'; a.uri root }
			feed.icon  '/images/kbd.gif'
			feed.logo  '/images/kbd.gif'
			#feed.entry atom_items($entries)

			#xml.items{ |items| yield items if block_given? }
		
			entries.each do |e|
				next if e.tags.find{ |tag| tag.name == 'hidden' }
		
				feed.entry do |i|
					i.id_            "http://www.keithdevens.com/weblog/#{e.id}"
					i.title          e.title
					i.published      e.creation_datetime.to_s
					i.updated        e.modification_datetime.to_s
					i.content(:type => 'xhtml') do |c|
						c << "<div xmlns=\"http://www.w3.org/1999/xhtml\">#{e.text_html}</div>"
					end
					i.link           nil, :href => e.permalink
				end
				#if($e['categories'])
				#	$item['category attr'] = array_values($e['categories']);
			end
		end
	end
	builder.to_xml
	#return weblog_sendFeed('atom', $time, $xml);
end
#
#function weblog_sendFeed($type, $time, $xml){
#	sendContentType($type);
#	header('Expires: '.gmdate('r', time()+15*60));
#	if(!httpConditionalGet($time))
#		echo XML_serialize($xml);
#	return true;
#}
