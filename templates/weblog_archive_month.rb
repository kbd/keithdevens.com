require_relative 'base'

class WeblogArchiveMonthTemplate < BaseTemplate
	def main
		h1 "Archive: #{@entries[0].creation_datetime.strftime('%B, %Y')}"

		div.weblog {
			previous_day = 0
			started = false
			@entries.each do |entry|
				day = entry.creation_datetime.day
				if day != previous_day
					h2.weblog(id: "day#{day}"){
						a.weblog entry.creation_datetime.strftime('%A, %B %e, %Y'), title: "permanent link for #{entry.creation_datetime.strftime('%B %d, %Y')}", href: entry.dateuri
					}
					previous_day = day
				end
				a entry.title, href: entry.permalink
				br
			end
		}
	end
end