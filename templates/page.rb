require_relative 'base'

class PageTemplate < BaseTemplate
  def main
    text! @page.text_html
  end

  def sidebar
    if not @recent_pages.nil? and not @recent_pages.empty?
      h3 'Recently changed pages'
      ol(class: 'flat-list'){
        @recent_pages.each { |p| page_link(p) }
      }
    end

    puts "pages length is #{@pages.length}"
    if not @pages.empty?
      h3 'Index'
      p {
        @pages.map{ |p| p.title[0].upcase }.uniq.each do |t|
          a t, href: "##{t}"
          text ' '
        end
      }

      h3 'All pages'
      @pages.group_by { |p| p.title[0].upcase }.each do |c, pages|
        h4 c, style: 'margin-bottom: .5em; background-color: #f9f9f9', id: c
        ol(style: 'margin-top: 0', class: 'flat-list'){
          pages.each{ |p| page_link(p) }
        }
      end
    end
  end

  def page_link(p)
    li {
      link = {href: p.permalink}
      link[:title] = p.description if p.description
      a p.title, link
    }
  end
end