require_relative 'base'

class WeblogArchiveTemplate < BaseTemplate
	def main
		h1 'Weblog Archive'

		table(style: "width: 100%"){
			tr {
				td(style: "vertical-align: top; text-align: left; width: 30%; border-collapse: collapse"){
					h2 'By date', style: "text-align: left"
					table(style: "padding: 0; margin: 0; border-collapse: collapse"){
						@years.each do |year, url|
							tr { td { a "Archive for #{year}", href: url } }
						end
					}
				}
				td(style: "vertical-align: top; text-align: left; width: 70%"){
					h2 'By tag', style: "text-align: left"
					ul(style: "margin: 0; padding: 0; list-style: none"){
						@tags.each do |tag|
							if tag.name != 'hidden'
								li(style: "display: inline; white-space: nowrap"){
									#<a style="font-size: ${8 + tag.weight}pt" href="$tag.uri">$tag.title</a>
									a tag.title, href: tag.uri
								}
								text ' '
							end
						end
					}
				}
			}
		}
	end
end