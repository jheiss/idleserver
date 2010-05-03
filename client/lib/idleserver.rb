##############################################################################
# Idle server agent
# Copyright 2010 AT&T Interactive
# http://idleserver.sourceforge.net/
# License: MIT (http://www.opensource.org/licenses/mit-license.php)
##############################################################################

STDOUT.sync = STDERR.sync = true # All outputs/prompts to the kernel ASAP

require 'uri'
require 'net/http'
require 'net/https'
require 'rexml/document'
require 'pp'
begin
  # Try loading facter w/o gems first so that we don't introduce a
  # dependency on gems if it is not needed.
  require 'facter'    # Facter
rescue LoadError
  require 'rubygems'
  require 'facter'
end

class IdleServer
  VERSION = 'trunk'
  CONFIGDIR = '/etc'
  
  class Agent
    def initialize(options={})
      @server = options[:server] ? options[:server] : 'http://idleserver'
      @debug = options[:debug] || false
      
      configfile = File.join(IdleServer::CONFIGDIR, 'idleserver.conf')
      if File.exist?(configfile)
        IO.foreach(configfile) do |line|
          line.chomp!
          next if (line =~ /^\s*$/);  # Skip blank lines
          next if (line =~ /^\s*#/);  # Skip comments
          line.strip!  # Remove leading/trailing whitespace
          key, value = line.split(/\s*=\s*/, 2)
          if key == 'server'
            # Warn the user, as this could potentially be confusing
            # if they don't realize there's a config file lying
            # around
            @server = value
            warn "Using server #{@server} from #{configfile}" if @debug
          end
        end
      end
    end
    
    # Gather all metrics and report them to the server
    def report
      metrics = []
      metrics << logins
      metrics << processes
      #metrics.each {|m| pp m}
      
      # Calculate overall idleness
      # Eventually we might want to weight some metrics more than others
      idleness = metrics.inject(0){|sum, m| sum + m[:idleness]} / metrics.size
      
      # Make sure the server URL ends in a / so that we can append paths
      # to it using URI.join
      if @server !~ %r{/$}
        @server << '/'
      end
      
      @serveruri = URI.parse(@server)
      
      # Create HTTP connection
      http = Net::HTTP.new(@serveruri.host, @serveruri.port)
      if @serveruri.scheme == "https"
        # Eliminate the OpenSSL "using default DH parameters" warning
        if File.exist?(File.join(CONFIGDIR, 'idleserver', 'dhparams'))
          dh = OpenSSL::PKey::DH.new(IO.read(File.join(CONFIGDIR, 'idleserver', 'dhparams')))
          Net::HTTP.ssl_context_accessor(:tmp_dh_callback)
          http.tmp_dh_callback = proc { dh }
        end
        http.use_ssl = true
        if File.exist?(File.join(CONFIGDIR, 'idleserver', 'ca.pem'))
          http.ca_file = File.join(CONFIGDIR, 'idleserver', 'ca.pem')
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        elsif File.directory?(File.join(CONFIGDIR, 'idleserver', 'ca'))
          http.ca_path = File.join(CONFIGDIR, 'idleserver', 'ca')
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end
      end
      http.start
      
      # Query for an existing entry for this client so we know whether
      # to PUT or POST
      fqdn = Facter['fqdn'].value
      clientqueryuri = URI.join(@server, "clients.xml?search[name]=#{fqdn}")
      puts "Getting client query from #{clientqueryuri}" if @debug
      get = Net::HTTP::Get.new(clientqueryuri.request_uri)
      response = http.request(get)
      if !response.kind_of?(Net::HTTPSuccess)
        $stderr.puts response.body
        # error! raises an exception
        response.error!
      end
      puts "Response from server:\n'#{response.body}'" if @debug
      clientxml = REXML::Document.new(response.body)
      clientid = nil
      if clientxml.elements['/clients/client/id']
        clientid = clientxml.elements['/clients/client/id'].text
      end
      puts "Client ID from query is #{clientid}" if @debug
      
      data = {:client => {:name => fqdn, :idleness => idleness}}
      # The server supports the Rails accepts_nested_attributes_for
      # mechanism, allowing us to update a client and all of its associated
      # metrics in one shot.
      # As best I can figure out from various blog posts and the like (haven't
      # bothered to test it myself yet) you can specify the nested attributes
      # as either a hash or an array.  Strictly speaking it should be an
      # array, but like other things in Rails it seems like it accepts a hash
      # with arbitrary keys and just ignores the keys.  Our flatten_hash
      # method doesn't support arrays, so convert our metrics array into a
      # hash using the metric name as the hash key.
      data[:client][:metrics_attributes] = metrics.inject({}) {|hash, m| hash[m[:name]] = m; hash}
      
      response = nil
      if clientid
        # PUT an update to the client
        
        # Query for existing metrics for this client, set id in existing
        # metrics so that they get updated, add _delete psuedo-metrics for
        # ones that should go away.
        metricqueryuri = URI.join(@server, "metrics.xml?search[client_id]=#{clientid}")
        puts "Getting metric query from #{metricqueryuri}" if @debug
        get = Net::HTTP::Get.new(metricqueryuri.request_uri)
        response = http.request(get)
        if !response.kind_of?(Net::HTTPSuccess)
          $stderr.puts response.body
          # error! raises an exception
          response.error!
        end
        puts "Response from server:\n'#{response.body}'" if @debug
        metricsxml = REXML::Document.new(response.body)
        metricsxml.elements.each('/metrics/metric') do |mxml|
          mid = mxml.elements['id'].text
          mname = mxml.elements['name'].text
          metric = metrics.find {|m| m[:name] == mname}
          if metric
            metric[:id] = mid
          else
            data[:client][:metrics_attributes][mname] = {:id => mid, '_delete' => true}
          end
        end
        
        clientputuri = URI.join(@server, "clients/#{clientid}.xml")
        puts "Putting client update to #{clientputuri}" if @debug
        put = Net::HTTP::Put.new(clientputuri.path)
        puts "Data:" if @debug
        p flatten_hash(data) if @debug
        put.set_form_data(flatten_hash(data))
        response = http.request(put)
      else
        # POST a new client
        clientposturi = URI.join(@server, 'clients.xml')
        puts "Posting client registration to #{clientposturi}" if @debug
        post = Net::HTTP::Post.new(clientposturi.path)
        puts "Data:" if @debug
        p flatten_hash(data) if @debug
        post.set_form_data(flatten_hash(data))
        response = http.request(post)
      end
      if !response.kind_of?(Net::HTTPSuccess)
        $stderr.puts response.body
        # error! raises an exception
        response.error!
      end
      puts "Response from server:\n'#{response.body}'" if @debug
      
    end
    
    def logins
      logins = []
      mostrecent = nil
      
      # FIXME: these should be user configurable
      threshold = 3 * 30  # ~ 3 months in days
      ignored_users = ['root', 'syi', 'msaltman', 'gnolan', 'pobrien', 'jheiss']
      #ignored_users = ['root', 'syi', 'msaltman', 'gnolan', 'pobrien']
      
      threshtime = Time.at(Time.now - threshold * 24 * 60 * 60)
      year = Time.now.year
      month = Time.now.mon
      # Seems lame to have to define this ourselves
      months = {'Jan' => 1, 'Feb' => 2, 'Mar' => 3, 'Apr' => 4,
                'May' => 5, 'Jun' => 6, 'Jul' => 7, 'Aug' => 8,
                'Sep' => 9, 'Oct' => 10, 'Nov' => 11, 'Dec' => 12}
      puts "Checking 'last' for recent logins" if @debug
      IO.popen('last') do |pipe|
        pipe.each do |line|
          line.chomp!
          puts "Processing line from last:" if @debug
          p line if @debug
          if line.empty?
            puts "Ignoring blank line" if @debug
            next
          end
          if line =~ /^wtmp begins /
            puts "Ignoring footer line" if @debug
            next
          end
          user, tty, source, timestamp = line.split(' ', 4)
          puts "user: #{user}, tty: #{tty}, source: #{source}, timestamp: #{timestamp}" if @debug
          # The pseudo entries for reboot have "system boot" in the tty field
          if tty == 'system' && source == 'boot'
            user, tty1, tty2, source, timestamp = line.split(' ', 5)
            tty = "#{tty1} #{tty2}"
            puts "Looks like a system boot line, now:" if @debug
            puts "user: #{user}, tty: #{tty}, source: #{source}, timestamp: #{timestamp}" if @debug
          end
          # The source field may be missing, leaving the day of the week
          # from the timestamp in the source variable
          if source =~ /^Mon|Tue|Wed|Thu|Fri|Sat|Sun$/
            timestamp = "#{source} #{timestamp}"
            source = nil
            puts "Source was empty, corrected timestamp is #{timestamp}" if @debug
          end
          # The timestamp field lacks a year, so we have to guess at the
          # correct year.  Entries are output by last in latest first order.
          # So any time we see the month go forward we can assume we've
          # rolled over to the previous year.  I.e.:
          # jheiss   pts/0     1.2.3.4    Mon Jan  4 19:29 - 19:36  (00:06)
          # jheiss   pts/0     1.2.3.4    Fri Jan  1 16:17 - 16:54  (00:36)
          # jheiss   pts/2     1.2.3.4    Wed Dec 30 18:54 - 18:54  (00:00)
          # jheiss   pts/1     1.2.3.4    Wed Dec 30 18:46 - 18:54  (00:08)
          wday, mon, mday = timestamp.split
          if months[mon] > month
            year -= 1
            puts "Month went forwards (#{month} -> #{months[mon]}), year adjusted to #{year}" if @debug
          end
          month = months[mon]
          # Parse the timestamp
          time = Time.local(year, mon, mday)
          # A sanity check
          warn "Time sanity check failed for #{timestamp}, #{year}" if time.strftime('%a') != wday
          
          # These next few checks could be sooner, but we put them after the
          # timestamp parsing so that the timestamp parsing sees more entries
          # in order to increase the likelihood that the timestamp parsing
          # will figure out each wraparound to the previous year.
          
          # Ignore the pseudo entries signifying system reboots
          if user == 'reboot' || user == 'shutdown'
            puts "Ignoring pseudo entry for #{user}" if @debug
            next
          end
          # Check for ignored users
          if ignored_users.include?(user)
            puts "Ignoring login from ignored user #{user}" if @debug
            next
          end
          
          # Now we can finally check and see if this login is recent
          if time >= threshtime
            puts "Login is recent, storing it" if @debug
            logins << line
            if !mostrecent || time > mostrecent
              puts "Login is most recent, updating most recent to #{time}" if @debug
              mostrecent = time
            end
          end
        end
      end
      
      # Calculate idleness
      # The idleness score for recent logins is based on two factors: number
      # of recent logins and the relative recentness of those logins.  I.e.
      # a login today indicates a lower probability of idleness than a login
      # two months ago.
      # Map number of recent logins onto 0..50
      idleness_count = 50
      if logins.size > 0 && logins.size < 10
        idleness_count = 25
      elsif logins.size >= 10
        idleness_count = 0
      end
      puts "Login count is #{logins.size}" if @debug
      puts "Idleness based on login count is #{idleness_count}" if @debug
      # Map most recent login onto 0..50
      idleness_recent = 50
      if mostrecent
        idleness_recent = ((Time.now - mostrecent) / (Time.now - threshtime) * 50).round
        puts "Most recent login was #{((Time.now - mostrecent) / (24 * 60 * 60)).round} days ago" if @debug
      end
      puts "Idleness based on recentness is #{idleness_recent}" if @debug
      # Calculate total idleness score
      idleness = idleness_count + idleness_recent
      puts "Total idleness is #{idleness}" if @debug
      
      {:name => 'logins', :idleness => idleness, :message => logins.join("\n")}
    end
    
    def processes
      processes = []
      
      # FIXME: Ignore processes of ignored users?
      
      # FIXME: these should be user configurable
      threshold = 3 * 30  # ~ 3 months in days
      threshtime = Time.at(Time.now - threshold * 24 * 60 * 60)
      ignored_processes = {
        'root' => [
                   # Kernel psuedo processes
                   %r{^migration/\d+},
                   %r{^ksoftirqd/\d+},
                   %r{^watchdog/\d+},
                   %r{^events/\d+},
                   'khelper',
                   'kthread',
                   'xenwatch',
                   'xenbus',
                   %r{^kblockd/\d+},
                   'kacpid',
                   %r{^cqueue/\d+},
                   'khubd',
                   'kseriod',
                   'kswapd0',
                   %r{^aio/\d+},
                   'kpsmoused',
                   %r{^ata/\d+},
                   'ata_aux',
                   %r{^scsi_eh_\d+},
                   'kstriped',
                   'kjournald',
                   'kauditd',
                   'udevd',
                   'hd-audio0',
                   %r{^kmpathd/\d+},
                   'kmpath_handlerd',
                   %r{^kondemand/\d+},
                   'krfcommd',
                   %r{^rpciod/\d+},
                   # Real processes
                   'init',
                   'acpid',
                   'agetty',
                   'atd',
                   'auditd',
                   'audispd',         # Goes with auditd
                   'automount',
                   'crond',
                   'cupsd',
                   'dhclient',
                   'gam_server',      # gamin file change notification
                   'gpm',
                   'hald-runner',     # hardware notification
                   'hald-addon-stor',
                   'hcid',            # Bluetooth
                   'hidd',            # Bluetooth
                   'klogd',
                   'master',          # postfix
                   'mingetty',
                   'nscd',
                   'pcscd',           # smart cards
                   'pdflush',
                   'rpc.idmapd',      # NFS
                   'sdpd',            # Bluetooth
                   'sendmail',
                   'smartd',
                   'snmpd',
                   'sshd',
                   'syslogd',
                   'yum-updatesd',
                   # Local stuff
                   'gmond', 'splunkd', 'opsdb_cron_wrap', 'etch_cron_wrapp'],
        'rpc' => ['portmap'],
        'dbus' => ['dbus-daemon'],
        'ntp' => ['ntpd'],
        'postfix' => ['pickup', 'qmgr'],
        'smmsp' => ['sendmail'],
        'avahi' => ['avahi-daemon'],
        # User is 'haldaemon', but that is too long and ps just shows the UID
        '68' => ['hald', 'hald-addon-acpi', 'hald-addon-keyb'],
        'xfs' => ['xfs'],
        'rpcuser' => ['rpc.statd'],
      }
      IO.popen('ps -eo user,pid,cputime,comm,lstart,args') do |pipe|
        pipe.each do |line|
          catch :nextline do
            user, pid, cputime, comm,
              lstartwday, lstartmon, lstartmday, lstarttime, lstartyear,
              args = line.split(' ', 10)
            line.chomp!
            puts "Processing line from ps:" if @debug
            p line if @debug
            if user == 'USER'
              puts "Skipping header line" if @debug
              throw :nextline
            end
            if ignored_processes[user]
              ignored_processes[user].each do |igproc|
                if (igproc.kind_of?(Regexp) && comm.match(igproc)) || igproc == comm
                  puts "Skipping ignored process #{user}, #{comm}" if @debug
                  throw :nextline
                end
              end
            end
            # Parse cputime
            # Format, according to ps(1): [dd-]hh:mm:ss
            cputimesec = 0
            if cputime =~ /^(\d\d)-/
              cpudays = $1
              cputime.sub!(/^\d\d-/, '')
              cputimesec += cpudays * 24 * 60 * 60
            end
            cpuhours, cpumins, cpusecs = cputime.split(':')
            cputimesec += cpuhours.to_i * 60 * 60
            cputimesec += cpumins.to_i * 60
            cputimesec += cpusecs.to_i
            puts "cputime #{cputime} parsed to #{cputimesec} seconds" if @debug
            # Parse lstart
            lstarthours, lstartmins, lstartsecs = lstarttime.split(':')
            start = Time.local(lstartyear, lstartmon, lstartmday, lstarthours, lstartmins, lstartsecs)
            lstartstring = "#{lstartwday} #{lstartmon} #{lstartmday} #{lstarttime} #{lstartyear}"
            puts "lstart #{lstartstring} parsed to #{start}" if @debug
            # A sanity check
            warn "start sanity check failed for #{lstartstring}" if start.strftime('%a') != lstartwday
            # Save, keeping the fields we need for calculating idleness as separate hash keys
            processes << {:line => line, :user => user, :cputime => cputimesec, :start => start}
          end
        end
        
        # Calculate idleness
        idleness = 0
        # The idleness score for processes is based on four factors: number
        # of processes, the relative recentness of those processes, the
        # amount of CPU time consumed by those processes, and whether any of 
        # those processes are running as a non-root user.
        # Map number of processes onto 0..25
        idleness_count = 25
        if processes.size > 0 && processes.size < 5
          idleness_count = 13
        elsif processes.size >= 5
          idleness_count = 0
        end
        puts "Process count is #{processes.size}" if @debug
        puts "Idleness based on process count is #{idleness_count}" if @debug
        # Map most recent process onto 0..25
        idleness_recent = 25
        mostrecent = processes.max{|a,b| a[:start] <=> b[:start]}
        if mostrecent
          puts "Most recent process:" if @debug
          pp mostrecent if @debug
          start = mostrecent[:start]
          # The process may be older than our threshold, we don't completely
          # discount old processes like with do with logins since a box might
          # be running long-running daemons.  But in that case we this aspect
          # of the idleness calculation to peg at 25.
          if start < threshtime
            idleness_recent = 25
          else
            idleness_recent = ((Time.now - start) / (Time.now - threshtime) * 25).round
          end
          puts "Most recent process was #{((Time.now - start) / (24 * 60 * 60)).round} days ago" if @debug
        end
        puts "Idleness based on recentness is #{idleness_recent}" if @debug
        # Map process CPU time onto 0..25
        idleness_cputime = 25
        total_cputime = processes.inject(0){|total, p| total + p[:cputime]}
        puts "Total CPU time is #{total_cputime}" if @debug
        if total_cputime > 0 && total_cputime < 10
          idleness_cputime = 13
        elsif total_cputime >= 10
          idleness_cputime = 0
        end
        puts "Idleness based on CPU time is #{idleness_cputime}" if @debug
        # Look for non-root processes
        idleness_nonroot = 25
        if processes.any?{|p| p[:user] != 'root'}
          idleness_nonroot = 0
        end
        puts "Idleness based on non-root is #{idleness_nonroot}" if @debug
        # Calculate total idleness score
        idleness = idleness_count + idleness_recent + idleness_cputime + idleness_nonroot
        puts "Total idleness is #{idleness}" if @debug
        
        puts "Processes:" if @debug
        pp processes.collect{|p| p[:line]} if @debug
        {:name => 'processes', :idleness => idleness, :message => processes.collect{|p| p[:line]}.join("\n")}
      end
    end
    
    def cpu
    end
    
    def memory
    end
    
    def network_io
    end
    
    def disk_io
    end
    
    private
      # http://marklunds.com/articles/one/314
      def flatten_hash(hash = params, ancestor_names = [])
        flat_hash = {}
        hash.each do |k, v|
          names = Array.new(ancestor_names)
          names << k
          if v.is_a?(Hash)
            flat_hash.merge!(flatten_hash(v, names))
          else
            key = flat_hash_key(names)
            key += "[]" if v.is_a?(Array)
            flat_hash[key] = v
          end
        end
      
        flat_hash
      end
      def flat_hash_key(names)
        names = Array.new(names)
        name = names.shift.to_s.dup 
        names.each do |n|
          name << "[#{n}]"
        end
        name
      end
    
  end # class Agent
end # class IdleServer

