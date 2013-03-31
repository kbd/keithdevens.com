require_relative 'base'

class QuoteTemplate < BaseTemplate
  def main
    ul {
      @quotes.each do |quote|
	      li {
		      #<?php if(logged_in()){?><a href="/admin/quotes/<?php e($q['Quote_Id'])?>">(edit)</a><?php }?>
		      text quote.text
          text! '&mdash;'
          conditional_link author(quote), quote.source_uri
          a raw(' &para;'), href: quote.permalink
	     }
      end
    }
  end

  def author(q)
    return q.source if (!q.author || q.author.empty?) and (q.source && !q.source.empty?)
    (q.author && !q.author.empty? ? q.author : 'unknown') + (q.source && !q.source.empty? ? " (#{q.source})" : '')
  end
end
