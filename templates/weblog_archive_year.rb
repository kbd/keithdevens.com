require_relative 'base'

class WeblogArchiveYearTemplate < BaseTemplate
	def main
		h1 "Weblog Archive for #{@year}"

		month = Date.new(@year, 1, 1)
		table(style: "text-align: right"){
			1.upto(4) do
				tr(style: "vertical-align: top"){
					1.upto(3) do
						td { cal_for_month(month >>= 1, @yearentries) }
					end
				}
			end
		}
	end

	def cal_for_month(month, entries)
		#month is a Date on the first of the given month
		day_names = Date::ABBR_DAYNAMES
		month_names = Date::MONTHNAMES

		uri = entries.empty? ? nil : Entry.monthuri(month.year, month.month)
		table.calendar {
			caption(style: "text-align: center; font-weight: bold"){
				conditional_link month_names[month.month], uri
			}
			
			#print day names
			tr { day_names.each { |day| th day } }

			text! '<tr>'
			#print empty cell for empty days
			td colspan: month.wday if month.wday > 0
			
			endofmonth = (month >> 1) - 1
			month.upto(endofmonth) do |date|
				#if it's not the first day of the month but we're on the first day of a week
				text! '</tr><tr>' if date.day != 0 and date.wday == 0
				td { conditional_link(date.day, Entry.dateuri(date), entries.key?(date)) }
			end

			#empty cell for the rest of the days
			rest = 6-endofmonth.wday
			td colspan: rest if rest > 0
			text! '</tr>'
		}
	end
end