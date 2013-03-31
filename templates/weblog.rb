require_relative 'base'

class WeblogTemplate < BaseTemplate
  def sidebar
    @search ||= ''
    ul {
      li { a 'RSS feed', title: 'RSS feed', href: '/weblog/rss' }
      li { a 'Atom feed', title: 'Atom feed', href: '/weblog/atom' }
      li { a 'Weblog archive', title: 'Weblog archive', href: '/weblog/archive' }
    }
    
    form.search_form(method: "get", action: "/weblog"){
      p {
        input type: "text", name: "search", value: @search
        br;
        input type: "submit", value: "Search weblog"
      }
    }
    p { text 'Contact me at:'; br; text 'my first name @ my domain' }
    
    text '@'; a 'twitter', href: "http://twitter.com/keithdevens"
    br; text '@'; a 'stackoverflow', href: "http://stackoverflow.com/users/837424/keith-devens"
    br; text '@'; a 'github', href: "https://github.com/kbd"
    br; text '@'; a 'reddit', href: "http://www.reddit.com/user/Keith"
    br; text '@'; a 'Hacker News', href: "http://news.ycombinator.com/user?id=kbd"

    if not @recent_comments.empty?
      p "Recent comments on #{@recent_comments.length} posts"

      now = DateTime.now
      @recent_comments.each do |c|
        #%#dayago = strtotime('-1 day');
        #%#url = weblog_getUrl('entry',array('creation_datetime'=>$comment['entry_creation_datetime'], 'name'=>$comment['entry_name'], 'id'=>$comment['entry_id']));
        div.weblog_recent_comment {
          p.entry_title {
            #span.new_comment_marker raw('new&rArr;') if c.creation_datetime + 1 >= now
            #<!-- &#x261E; right-pointing finger--></span>
            a c.entry.title, href: c.entry.permalink
            p.comment_body c.title
            p.comment_date {
              strong { conditional_link c.name, c.website }; text ': '
              a c.creation_datetime.strftime('%b %e, %l:%M%P'), href: c.permalink
            }
          }
        }
      end
    end
  end

  def main
    div.weblog {
      @entries.group_by { |e| e.creation_datetime.strftime('%A, %B %d, %Y') }.each do |day, entries|
        h2 { a day, title: "permanent link for #{day}", href: entries[0].dateuri }

        entries.each do |entry|
          display_entry(entry)
        
          if @individual
            h3 'Comments'
            display_comments(entry)
            if not entry.allow_comments
              p{ em 'Comments disabled on this entry' }
            else
              display_comment_form(@comment_form)
            end
          end
        end
      end
    }
  end

  def display_entry(entry)
    div(id: "id#{entry.id}", class: "weblog_entry#{(entry.tags.find {|tag| tag == 'linkblog'} and not individual) ? ' linkblog' : ''}"){
      editlink(entry)
      h3 { a entry.title, href: entry.permalink } if entry.title

      text! entry.text_html
      
      div.entry_footer {
        display_time(entry)
        cc = entry.comment_count
        if entry.allow_comments or cc > 0
          span.separator ' | '
          a(href: "#{entry.permalink}#comments"){
            # "1 Comment" or "5 Comments" or "Comments?"
            text "#{cc} " if cc > 0
            text "Comment#{'s' if cc != 1}#{'?' if cc == 0}"
          }
        end
        display_tags(entry)
      }
    }
  end

  def display_tags(entry)
    tags = entry.tags.select{ |t| t.name != 'linkblog' }
    if not tags.empty?
      span.separator raw(' | &isin; ')
      span.tags {
        text '{'
        tags.each_with_index do |tag,i|
          a tag.title, href: tag.uri
          text ', ' if (i != tags.length - 1)
        end
        text '}'
      }
    end
  end

  def display_comment_form(form)
    preview_text = 'PREVIEW comment'
    post_text = 'POST comment'
    preview_field_name = '__preview'

    #it'd be nice if there were an 'is_submitted' method
    is_preview = !form[preview_field_name].nil? || !form['__submit'].nil?

    form.form do |f|
      if form.has_errors
        h3.error "Your form has errors"
        form.errors.each{ |e| p.error e }
        form.field_errors.each{ |f,e| p.error "#{f} - #{e}" }
      end
      
      table.weblog_comment_form {
        tr {
          td {
            f.label :name, 'Name'; br
            text! '(will be your <em>IP address</em> if blank)'; br
            f.text :name
          }
          td {
            f.label :email, 'E-mail (optional; not displayed)'; br
            text! '(Do it for the <a href="http://gravatar.com/">gravatar</a>!)'; br
            f.text :email
          }
          td {
            br
            f.label :website, 'Website (optional)'; br
            f.text 'website'
          }
        }
        tr {
          td(colspan: 3){
            f.label :text, 'Comment'; br
            f.textarea :text, rows: 15, cols: 64
          }
        }
        tr {
          td(colspan: 3){
            f.submit preview_text, name: preview_field_name
            text ' '
            if !is_preview || form.has_errors
              text "(You must preview before posting)"
            else
              f.submit post_text
              br
            end
          }
        }
      }
    end
  end

  def display_comment(comment)
    puts "Comment is #{comment.inspect}"
    h4(id: "comment#{comment.id}"){
      conditional_link comment.name, comment.website
      span.comment_time {
        text ' ('
        a "@#{comment.creation_datetime.strftime('%Y-%m-%d %H:%M')}", href: "#{comment.permalink}"
        text ')'
      }
    }
    div.comment {
      text! comment.gravatar_image
      text! comment.text_html
    }
  end

  def display_comments(entry)
    entry.comments.each{ |c| display_comment c }

    if @preview_comment
      h3 "Previewing comment (your comment is not yet saved!)", style: 'color: green'
      display_comment @preview_comment
    end
  end

  def format_tz(dt)
    #dt.zone looks like "-05:00", change it to "-5", ignoring the leading zero.
    #If it's, say, "-05:30", keep the ':30'
    z = dt.zone.sub(/([+-])0?(\d+)(?::00|(:\d+))/, '\1\2\3')
    " (utc#{z})"
  end

  def display_time(entry)
    ct, mt = entry.creation_datetime, entry.modification_datetime
    span.weblog_time {
      a.created_time "@#{ct.strftime('%H:%M')}", rel: "bookmark", href: entry.permalink, title: "permanent link for '#{entry.title}'"
      span.timezone format_tz(ct)
      if ct != mt
        span.modified_time {
          text! " &Delta;"
          text mt.strftime('%Y-') if ct.year != mt.year #if it's a different year, show the year
          text mt.strftime('%b-%d') if ct.yday != mt.yday #if it's a different day, show the day
          text " @#{mt.strftime('%H:%M')}"
        }
        span.timezone format_tz(mt) if ct.offset != mt.offset
      end
    }
  end
end