require 'redcarpet'

RENDER_OPTIONS = {
  filter_html: true,
  hard_wrap: true
}

EXTENSIONS = {
  no_intra_emphasis: true,
  tables: true,
  fenced_code_blocks: true,
  autolink: true,
  strikethrough: true,
  lax_spacing: true,
  superscript: true,
}

renderer = Redcarpet::Render::HTML.new(render_options=RENDER_OPTIONS)
Markdown = Redcarpet::Markdown.new(renderer, EXTENSIONS)
