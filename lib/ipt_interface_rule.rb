class Ipt_interface::Rule
  @@list = Wref_map.new
  
  def self.list(args = {}, &block)
    enum = Enumerator.new do |yielder|
      output = %x[iptables -vvnL --line-numbers]
      
      #Add the prerouting chain as well.
      output << "\n\n"
      output << %x[iptables -t nat -vvnL --line-numbers]
      
      chain_enum = Enumerator.new do |yielder|
        output.scan(/Chain ([A-Z]+)([\s\S]+?)(\n\n|libiptc)/) do |match|
          cname = match[0].downcase.to_sym
          
          expect = 0
          match[1].scan(/^(\d+)\s+([\dKMTG]+)\s+([\dKMTG]+?)\s+([A-Z]+?)\s+([a-z]+?)\s+(\S+)\s+(\S+)\s+(\S+)\s+([\d\.\/]+)\s+([\d\.\/]+)\s+?(.*?)$/) do |match_rule|
            expect += 1
            no = match_rule[0].to_i
            
            #If expect isnt the same, we have missed a rule, which will corrupt the system.
            raise "Expected chain number to be #{expect} but it wasnt: #{no}." if no != expect
            
            data_text = match_rule[10].strip
            terms = []
            actions = []
            
            regex = /state\s+(\S+)/
            data_text.scan(regex) do |match|
              states = match[0].split(",").map{|ele| ele.downcase.to_sym}
              terms << {:type => :state, :states => states}
            end
            
            data_text.split(/\s+/).each do |data_i|
              if data_i == "udp" or data_i == "tcp" or data_i == "icmp"
                terms << {:type => :protocol, :protocol => data_i.to_sym}
              elsif data_match = data_i.match(/^dpt:(\d+)$/)
                terms << {:type => :destination_port, :port => data_match[1].to_i}
              elsif data_match = data_i.match(/^to:([\d\.]+):(\d+)$/)
                actions << {:type => :to, :ip => data_match[1], :port => data_match[2].to_i}
              end
            end
            
            id = "#{cname}_#{no}"
            
            yielder << {
              :id => id,
              :chain => cname,
              :no => no,
              :packages_text => match_rule[1],
              :bytes_text => match_rule[2],
              :target => match_rule[3].downcase.to_sym,
              :protocol_text => match_rule[4].downcase.to_sym,
              :iface_in => match_rule[6].to_sym,
              :iface_out => match_rule[7].to_sym,
              :data_text => data_text,
              :terms => terms,
              :actions => actions
            }
          end
        end
      end
      
      mode = nil
      expect = 0
      output.scan(/Entry (\d+) \((\d+)\):([\s\S]+?)\n\n/) do |match|
        entry = match[0].to_i
        
        #It is allowed to reset entry to 0, because the prerouting table will do so.
        if entry == 0
          if mode == nil
            mode = :normal
          elsif mode == :normal
            mode = :nat
          else
            raise "Unknown next mode from: #{mode}"
          end
          
          expect = 0
        end
        
        #If expect isnt the same, we have missed a rule, which will corrupt the system.
        raise "Entry was expted to be #{expect} but it wasnt: #{entry}." if entry != expect
        
        begin
          data = chain_enum.next
        rescue StopIteration
          data = {}
        end
        
        data[:entry] = entry
        match[2].scan(/(.+?)(: |=)(.+?)$/) do |match_prop|
          key = match_prop[0].downcase.gsub(/\s+/, "_").to_sym
          val = match_prop[2]
          
          if key == :src_ip or key == :dst_ip
            data["#{key}_ip".to_sym] = val.split("/")[0]
            data["#{key}_mask".to_sym] = val.split("/")[1]
          elsif key == :interface and match_iface = val.match(/^`(.+?)'/) and match_iface[1][1] != "/"
            #If interface is already given, check that it is the same on the matched text, to be sure it isnt the wrong rule.
            if data[:iface] and data[:iface].to_s != match_iface[1]
              raise "Interface doesnt match: #{data[:iface]} vs #{match_iface[1]}."
            end
            
            data[:iface] = match_iface[1].to_sym
          elsif key == :match_name and match_name = val.match(/^`(.+?)'/)
            #If protocol is already given, check that it is the same on the matched text, to be sure it isnt the wrong rule.
            if match_name[1] == "udp" or match_name[1] == "tcp" and data[:protocol_text] and match_name[1] != data[:protocol_text].to_s
              raise sprintf(_("Protocol does not match matc-name: '%1$s', '%2$s'.") + " #{match_prop} #{data} #{val}", match_name[1], data[:protocol_text])
            end
            
            data[:protocol_text] = match_name[1].downcase.to_sym if !data[:protocol_text]
          end
          
          data[key] = val
        end
        
        if !data.key?(:id)
          data[:id] = "entry_#{mode}_#{data[:entry]}"
        end
        
        if rule = @@list.get!(entry)
          rule.data = data
        else
          rule = Ipt_interface::Rule.new
          rule.data = data
          
          @@list[data[:id]] = rule
        end
        
        yielder << rule
        expect += 1
      end
    end
    
    if block
      enum.each(&block)
      return nil
    else
      return enum
    end
  end
  
  def self.by_entry(entry)
    return self.by(:entry => entry.to_i)
  end
  
  def self.by(args)
    #Check weak map.
    @@list.each do |id, rule|
      found = true
      
      args.each do |key, val|
        if rule.data[key] != val
          found = false
          break
        end
      end
      
      return rule if found
    end
    
    #Go through list.
    self.list do |rule|
      found = true
      
      args.each do |key, val|
        if rule.data[key] != val
          found = false
          break
        end
      end
      
      return rule if found
    end
    
    #Not found.
    raise sprintf(_("Could not find a rule by that data: '%s'."), "#{args}")
  end
  
  attr_accessor :data
  
  #Returns the URL for making a link to the rule in the "Ipt_interface"-app.
  def url
    return "?show=rule_show&rule_id=#{self.id}"
  end
  
  #Returns the current entry-number for the rule.
  def entry
    return @data[:entry]
  end
  
  alias id entry
  
  def iface_in
    return @data[:iface_in]
  end
  
  def iface_out
    return @data[:iface_out]
  end
  
  def dst_ip
    return @data[:dst_ip_ip]
  end
  
  def src_ip
    return @data[:src_ip_ip]
  end
  
  def protocol
    return @data[:protocol_text]
  end
  
  #Returns a hash that can be used to validate, if this is the expected rule.
  def hash
    strs = []
    @data.each do |key, val|
      strs << "#{key}:#{val}"
    end
    
    return Digest::MD5.hexdigest(strs.join(","))
  end
  
  def name
    if @data.key?(:chain) and @data.key?(:no)
      return "#{@data[:chain].to_s[0].upcase}#{@data[:chain].to_s[1, @data[:chain].length]} #{@data[:no]}"
    else
      return sprintf(_("Entry %s"), self.entry)
    end
  end
  
  def name_html
    return Knj::Web.html(self.name)
  end
  
  def html
    return "<a href=\"#{Knj::Web.ahref_parse(self.url)}\">#{self.name_html}</a>"
  end
  
  #Deletes the rule from the chain.
  def delete
    raise "No chain on rule - cant identify it." if !@data.key?(:chain)
    raise "No chain-number on rule - cant identify it." if !@data.key?(:no)
    %x[iptables -D #{@data[:chain].to_s.upcase} #{@data[:no]}]
  end
end