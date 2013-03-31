require 'CGI'
require 'set'

require 'erector'

class ErectorWrapper
  def initialize(caller, form)
    @caller, @form = caller, form
  end
  def method_missing(m, *args, &block)
    @caller.send 'text!', @form.send(m, *args, &block)
  end
end

class FormHelper
  attr_accessor :action
  attr_accessor :method
  attr_accessor :save_method
  attr_reader :errors
  attr_reader :field_errors

  def initialize(name, model)
    @name = name
    @model = model
    @action = ''
    @method = 'POST'
    @errors = []
    @field_errors = {}
    @form_values = {}
    @save_method = 'save'
  end

  def html(s)
    s ? CGI::escapeHTML(s) : ''
  end

  def process(req, opts={})
    #pass in the request, it pulls out the variables and populates
    #the object, returns true if success, false on failure.
    #if failure, a field_errors property as well as an errors property
    #are populated. field_errors is a hash containing an error message
    #per field, and errors is a list of error messages applying to the
    #form as a whole
    #field_errors gets populated upon an exception when assigning to a field

    #todo: instead of 'save_method', possibly just take a block and let
    #the caller call whatever save method they want

    call_save = opts.fetch(:save, true)

    @form_values = req[@name]
    if not @form_values
      @errors << "No form values passed"
      return false
    end

    success = true

    #try writing each value, catch exceptions and record any errors
    puts "Model whitelist is #{@model.whitelist.inspect}"
    #make strings out of the whitelist, instead of making symbols out of the
    #form tags, because ruby saves all symbols and you open yourself up to
    #someone using up all your memory if you translate user input into symbols
    whitelist_strs = @model.whitelist.map{ |s| s.to_s }.to_set
    @form_values.each do |k,v|
      next if k.start_with? '__'
      begin
        raise "Invalid field for assignment: '#{k}'" if !whitelist_strs.include? k
        @model.send("#{k}=", v)
      rescue Exception => e
        @field_errors[k] = e
        success = false
      end
    end

    #for any whitelisted values, set to nil if not provided by the form
    #this lets form elements have a default but actually get set by
    #a form submission even if it doesn't have that field
    (whitelist_strs - @form_values.keys).each{ |w| @model.send("#{w}=", nil) }

    if success
      call_save ? save : true
    else
      false
    end
  end

  def save
    #try saving the whole object, catch exception and record error
    return false if !errors.empty? || !field_errors.empty?
    begin
      @model.send(save_method) #returns self (which is truthy) on success
    rescue Exception => e
      @errors << e
      false
    end
  end

  def has_errors
    !(@errors.empty? && @field_errors.empty?)
  end

  def field_name(fieldname)
    "#{@name}[#{fieldname}]"
  end

  def field_id(fieldname)
    "#{field_name(fieldname)}_id"
  end

  def value(fieldname)
    #gets the value from the underlying model, not from the form submission like []
    @model.send(fieldname)
  end

  def [](fieldname)
    @form_values[fieldname]
  end

  def form(params={}, &block)
    m = params.fetch(:method, @method)
    a = params.fetch(:action, @action)
    p = params.reject{|k,v| k == :method || k == :action}
    i = "#{@name}_form"
    f = "<form method=\"#{html(m)}\" action=\"#{html(a)}##{i}\" id=\"#{i}\" accept-encoding=\"utf-8\" #{format_params(p)}>"

    return f if not block #method syntax, else do block syntax which is normally what you want

    caller = eval("self", block.binding)
    w = ErectorWrapper.new(caller, self)
    caller.send 'widget', Erector.inline do
      text! f
      block.call(w)
      text! '</form>'
    end
  end

  def endform()
    "</form>"
  end

  def format_params(params)
    params.map{ |k,v| "#{k}=\"#{html(v.to_s)}\"" if not v.nil?}.join(' ')
  end

  def tag(tagname, fieldname, params={})
    content = (yield || value(fieldname) if block_given?)
    value = params['value']
    if fieldname && !content && !params.include?('value')
      #get the value from the underlying model if it's...
      #not passed in, no content is provided, and there's a fieldname
      value = value(fieldname)
    end

    v = value ? " value=\"#{html(value.to_s)}\"" : ''
    nid = "name=\"#{field_name(fieldname)}\" id=\"#{field_id(fieldname)}\"#{v}" if fieldname

    tail = content || block_given? ? ">#{html(content)}</#{tagname}>" : ' />'
    "<#{tagname} #{nid} #{format_params(params)}#{tail}"
  end

  def label(fieldname, text)
    "<label for=\"#{field_id(fieldname)}\">#{text}</label>"
  end

  def text(fieldname, params={})
    input(fieldname, params.merge(type: 'text'))
  end

  def password(fieldname, params={})
    input(fieldname, params.merge(type: 'password'))
  end

  def checkbox(fieldname, params={})
    params['type'] = 'checkbox'
    params['value'] = nil #so it doesn't print value=...
    params['checked'] = 'checked' if value(fieldname)
    input(fieldname, params)
  end

  def submit(value, params={})
    name = params.fetch(:name, '__submit')
    tag('input', nil, params.merge(name: field_name(name), value: value, type: 'submit'))
  end

  def input(fieldname, params)
    tag('input', fieldname, params)
  end

  def textarea(fieldname, params)
    tag('textarea', fieldname, params){nil} #textarea always needs a closing element apparently
  end

  def dropdown(fieldname, params, options)
    #if($multi){?>[]" multiple="multiple"<?php }else{?>"<?php }
    v = value(fieldname)
    tag('select', fieldname, params) do
      options.each do |key, description|
        tag('option', nil, value: key, selected: ('selected' if v == key)){ html(description) }
      end
    end
  end
end