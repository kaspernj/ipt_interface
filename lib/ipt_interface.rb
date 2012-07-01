class Ipt_interface
  def self.quick_start(args)
    ii = Ipt_interface.new(args)
    ii.join
  end
  
  #Autoloader for subclasses.
  def self.const_missing(name)
    require "#{File.dirname(__FILE__)}/ipt_interface_#{name.to_s.downcase}.rb"
    return Ipt_interface.const_get(name)
  end
  
  def initialize(args)
    require "rubygems"
    require "knjappserver"
    require "knjrbfw"
    require "sqlite3"
    
    config_path = "#{Knj::Os.homedir}/.ipt_interface"
    Dir.mkdir(config_path) if !File.exists?(config_path)
    
    db_path = "#{config_path}/database.sqlite3"
    
    @db = Knj::Db.new(
      :type => "sqlite3",
      :path => db_path,
      :return_keys => "symbols"
    )
    
    path = File.realpath("#{File.dirname(__FILE__)}/../")
    @appsrv = Knjappserver.new(
      :doc_root => "#{path}/doc_root",
      :port => args[:port],
      :db => @db,
      :debug => false,
      :locales_root => "#{path}/locales",
      :locales_gettext_funcs => true,
      :locale_default => "en_GB",
    )
    @appsrv.define_magic_var(:_site, self)
    @appsrv.define_magic_var(:_ob, @ob)
    @appsrv.define_magic_var(:_db, @db)
    
    @appsrv.start
  end
  
  def join
    @appsrv.join if @appsrv
  end
  
  def header(title)
    return "<h1>#{Knj::Web.html(title)}</h1>"
  end
  
  def boxt(title, width = "100%")
    if Knj::Php.is_numeric(width)
      width = "#{width}px"
    end
    
    html = "<div class=\"box\">"
    
    if title
      html << "<div class=\"box_title\">#{Knj::Web.html(title)}</div>"
    end
    
    return html
  end
  
  def boxb
    return "</div>"
  end
end