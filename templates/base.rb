require 'erector'

class BaseTemplate < Erector::Widgets::Page
  def doctype
    '<!DOCTYPE html>'
  end

  def page_title
    "Keith Devens #{"- #{@title}" if @title}"
  end

  def conditional_link(txt, link, condition=true)
    if condition and not (link.nil? or link.empty?)
      a txt, href: link
    else
      text txt
    end
  end

  def head_content
    super
    
    #openid
    link rel: 'openid2.provider', href: 'https://www.google.com/accounts/o8/ud?source=profiles'
    link rel: 'openid2.local_id', href: 'http://www.google.com/profiles/keith.devens'

    link rel: 'stylesheet', type: 'text/css', href: '/static/style.css'
    meta name: 'keywords', content: @keywords if @keywords
    meta name: 'description', content: @description if @description
    @meta.each{ |item| meta item } if @meta
    @links.each{ |item| link item } if @links
    @css_files.each{ |file| link rel: 'stylesheet', type: 'text/css', href: file } if @css_files
    @javascript_files.each{ |file| script type: 'text/javascript', src: file } if @javascript_files
    style type: 'text/css' do @css end if @css
    script type: 'text/javascript', defer:'defer' do @javascript end if @javascript
  end 

  #override in subclasses. called from body_content, which is a special Erector method
  def main
    if @content.is_a? Proc
      instance_exec &@content
    else
      text! @content
    end
  end

  def sidebar
  end

  def google_analytics
#     javascript <<eos
# var _gaq = _gaq || [];
# _gaq.push(['_setAccount', 'UA-38360841-1']);
# _gaq.push(['_trackPageview']);

# (function() {
#   var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
#   ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
#   var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s);
# })();
# eos
  end

  def body_content
    breadcrumbs

    div.content! {
      prevnext
      main
      prevnext
    }

    div.sidebar! { sidebar }
    div.footer! raw('&copy; Keith Devens, 1998-2013')
    
    google_analytics
  end

  def prevnext
    return if not @prevnext
    table.prevnext {
      tr {
        td(style: 'text-align: left'){
          if @prevnext.prev
            text! '&larr;&nbsp;'
            a @prevnext.prev.name, href: @prevnext.prev.uri
          end
        }
        td(style: 'text-align: right'){
          if @prevnext.next
            a @prevnext.next.name, href: @prevnext.next.uri
            text! '&nbsp;&rarr;'
          end
        }
      }
    }
  end

  def breadcrumbs(separator='&raquo;')
    return if @breadcrumbs.nil? or @breadcrumbs.empty?
    div.breadcrumbs do
      @breadcrumbs.each_with_index do |b,i|
        if i == @breadcrumbs.length-1 #last breadcrumb
          text b.name
        else
          a b.name, href: b.uri, title: b.title
          text! " #{separator} "
        end
      end
    end
  end

  def logged_in
    @session[:logged_in]
  end

  def editlink(obj) 
    if logged_in
      div(style: "float: right"){
        a 'Edit', href: "/admin/#{obj.class}?id=#{obj.id}"
      }
    end
  end

  def display_form_errors(form)
    return if !form.has_errors

    h3.error "Your form has errors"
    form.errors.each{ |e| p.error e }
    ul.error {
      form.field_errors.each_value{ |e| li e }
    }
  end
end
