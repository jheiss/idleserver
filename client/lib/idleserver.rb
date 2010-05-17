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
  
  # Seems lame to have to define these ourselves
  MONTHS = {'Jan' => 1, 'Feb' => 2, 'Mar' => 3, 'Apr' => 4,
            'May' => 5, 'Jun' => 6, 'Jul' => 7, 'Aug' => 8,
            'Sep' => 9, 'Oct' => 10, 'Nov' => 11, 'Dec' => 12}
  WDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
  
  class Agent
    def initialize(options={})
      @server = options[:server] ? options[:server] : 'http://idleserver'
      @debug = options[:debug] || false
      
      @ignored_users = ['root']
      @login_threshold = 3 * 30  # ~ 3 months in days
      @ignored_users_processes_ignored = true
      @keep_root_processes = true
      @process_threshold = 3 * 30  # ~ 3 months in days
      
      @loginthreshtime = Time.at(Time.now - @login_threshold * 24 * 60 * 60)
      @processthreshtime = Time.at(Time.now - @process_threshold * 24 * 60 * 60)
      
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
          elsif key == 'ignored_users'
            @ignored_users = value.split(/\s*,\s*/)
          elsif key == 'login_threshold'
            @login_threshold = value.to_i
          elsif key == 'ignored_users_processes_ignored'
            if value == 'false'
              @ignored_users_processes_ignored = false
            else
              @ignored_users_processes_ignored = true
            end
          elsif key == 'keep_root_processes'
            if value == 'false'
              @keep_root_processes = false
            else
              @keep_root_processes = true
            end
          elsif key == 'process_threshold'
            @process_threshold = value.to_i
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
      
      file_by_os = {
        'Linux' => '/var/log/wtmp',
        'SunOS' => '/var/adm/wtmpx',
      }
      
      files = [nil]
      file = file_by_os[Facter['kernel'].value]
      if !file
        raise "No support for logins on operating system #{Facter['kernel'].value}"
      end
      Dir.glob("#{file}.*") do |f|
        # Ignore files older than the threshold
        if File.mtime(f) < @loginthreshtime
          puts "Ignoring login log file #{f}, timestamp #{File.mtime(f)} is older than threshold" if @debug
        else
          files << f
        end
      end
      
      files.each do |f|
        filelogins, filemostrecent = logins_from_file(f)
        logins.concat(filelogins)
        if filemostrecent && (!mostrecent || filemostrecent > mostrecent)
          puts "Login is most recent, updating most recent to #{filemostrecent}" if @debug
          mostrecent = filemostrecent
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
        idleness_recent = ((Time.now - mostrecent) / (Time.now - @loginthreshtime) * 50).round
        puts "Most recent login was #{((Time.now - mostrecent) / (24 * 60 * 60)).round} days ago" if @debug
      end
      puts "Idleness based on recentness is #{idleness_recent}" if @debug
      # Calculate total idleness score
      idleness = idleness_count + idleness_recent
      puts "Total idleness is #{idleness}" if @debug
      
      {:name => 'logins', :idleness => idleness, :message => logins.join("\n")}
    end
      
    def logins_from_file(file=nil)
      logins = []
      mostrecent = nil
      
      year = nil
      previously_seen_month = nil
      if file
        year = File.mtime(file).year
        previously_seen_month = File.mtime(file).mon
      else
        year = Time.now.year
        previously_seen_month = Time.now.mon
      end
      cmd = nil
      if file
        cmd = "last -f #{file}"
      else
        cmd = 'last'
      end
      puts "Checking '#{cmd}' for recent logins" if @debug
      IO.popen(cmd) do |pipe|
        pipe.each do |line|
          line.chomp!
          puts "Processing line from last:" if @debug
          p line if @debug
          if line.empty?
            puts "Ignoring blank line" if @debug
            next
          end
          if line =~ /^wtmp begins / ||
            (file && line =~ /^#{File.basename(file)} begins /)
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
          if MONTHS[mon] > previously_seen_month
            year -= 1
            puts "Month went forwards (#{previously_seen_month} -> #{MONTHS[mon]}), year adjusted to #{year}" if @debug
          end
          previously_seen_month = MONTHS[mon]
          # A long gap in logins can throw us off.  In this example the May
          # logins are in 2010, the older logins appear to just be in the
          # previous month, but the weekday is wrong.  Apr 2, 2010 is a
          # Friday.  Apr 2, 2009 is a Thursday.
          # jheiss   pts/1        1.2.3.4      Wed May 12 11:49   still logged in   
          # jheiss   pts/0        1.2.3.4      Wed May 12 11:41   still logged in   
          # jheiss   pts/0        1.2.3.4      Thu Apr  2 18:59 - 19:26  (00:26)    
          # jheiss   pts/0        1.2.3.4      Thu Apr  2 18:54 - 18:58  (00:04)    
          # So we keep trying older years until we find one that matches up
          time = nil
          year.downto(year-10) do |y|
            # Parse the timestamp
            time = Time.local(y, mon, mday)
            # A sanity check
            if time.strftime('%a') == wday
              year = y
              break
            else
              puts "Time sanity check failed for #{timestamp}, #{y}" if @debug
            end
          end
          
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
          if @ignored_users.include?(user)
            puts "Ignoring login from ignored user #{user}" if @debug
            next
          end
          
          # Now we can finally check and see if this login is recent
          if time >= @loginthreshtime
            puts "Login is recent, storing it" if @debug
            logins << line
            if !mostrecent || time > mostrecent
              puts "Login is most recent for this file, updating file most recent to #{time}" if @debug
              mostrecent = time
            end
          end
        end
      end
      [logins, mostrecent]
    end
    
    def processes
      processes = []
      
      # FIXME: these should be user configurable
      ignored_processes = {
        'root' => [
                   # Kernel psuedo processes
                   %r{^aio/\d+},
                   %r{^ata/\d+},
                   'ata_aux',
                   'bnx2x',
                   'cciss_scan00',
                   %r{^cqueue/\d+},
                   %r{^events/\d+},
                   'hd-audio0',
                   'kacpid',
                   'kauditd',
                   %r{^kblockd/\d+},
                   'kedac',
                   'khelper',
                   'khubd',
                   'kipmi0',
                   'kjournald',
                   %r{^kmpathd/\d+},
                   'kmpath_handlerd',
                   %r{^kondemand/\d+},
                   'kpsmoused',
                   'krfcommd',
                   'kseriod',
                   %r{^ksoftirqd/\d+},
                   'kstriped',
                   %r{^kswapd\d+},
                   'kthread',
                   %r{^migration/\d+},
                   'phpd_event',
                   'rpciod',
                   %r{^rpciod/\d+},
                   %r{^scsi_eh_\d+},
                   'udevd',
                   %r{^watchdog/\d+},
                   'xenwatch',
                   'xenbus',
                   # These iSCSI and InfiniBand processes are only showing up
                   # on a small number of systems running a few particular
                   # apps (although those apps don't appear to using iSCSI
                   # currently and we don't have any InfiniBand hardware). 
                   # Arguably they should be excluded since it seems that the
                   # mere fact of installing the associated RPMs causes these
                   # kernel modules to get loaded and thus these process
                   # entries to appear.
                   # %r{^ib_cm/\d+},
                   # 'ib_addr',
                   # 'ib_mcast',
                   # 'ib_inform',
                   # 'local_sa',
                   # 'iw_cm_wq',
                   # 'rdma_cm',
                   # 'iscsi_eh',
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
                   'irqbalance',
                   # See comment about iSCSI above
                   # 'iscsid',
                   'klogd',
                   'lockd',           # NFS
                   'master',          # postfix
                   'mingetty',
                   'nscd',
                   'pcscd',           # smart cards
                   'pdflush',
                   'rpc.idmapd',      # NFS
                   'rpc.statd',       # NFS
                   'sdpd',            # Bluetooth
                   'sendmail',
                   'smartd',
                   'snmpd',
                   'sshd',
                   'syslogd',
                   'xinetd',
                   'yum-updatesd',
                   # HP monitoring agents
                   'hpasmd',
                   'hpasmlited',
                   'hpasmpld',
                   'cmaeventd',
                   'cmafcad',
                   'cmahealthd',
                   'cmahostd',
                   'cmaidad',
                   'cmaided',
                   'cmanicd',
                   'cmapeerd',
                   'cmaperfd',
                   'cmasasd',
                   'cmascsid',
                   'cmasm2d',
                   'cmastdeqd',
                   'cmathreshd',
                   # Local stuff
                   'gmond',
                   'splunkd',
                   'opsdb_cron_wrap', 'opsdb',
                   'etch_cron_wrapp', 'etch',
                   # sh and sleep processes are associated with check_ntpd
                   'check_ntpd', 'sh', 'sleep',
                   'randomizer'],
        'avahi' => ['avahi-daemon'],     # Zeroconf service discovery
        'canna' => ['cannaserver'],      # Japanese input
        'dbus' => ['dbus-daemon', 'dbus-daemon-1'],
        'hpsmh' => ['hpsmhd'],           # HP System Management Homepage
        'htt' => ['htt', 'htt_server'],  # Unicode input
        'nscd' => ['nscd'],
        'ntp' => ['ntpd'],
        'postfix' => ['pickup', 'qmgr'],
        'rpc' => ['portmap'],
        'rpcuser' => ['rpc.statd'],
        'smmsp' => ['sendmail'],
        'xfs' => ['xfs'],
        # User is 'haldaemon', but that is too long and ps just shows the UID
        '68' => ['hald', 'hald-addon-acpi', 'hald-addon-keyb'],
      }
      pscmd = 'ps -eo user,pid,cputime,comm,lstart,args'
      IO.popen(pscmd) do |pipe|
        pipe.each do |line|
          catch :nextline do
            line.chomp!
            puts "Processing line from ps:" if @debug
            p line if @debug
            psparts = line.split(' ')
            user = psparts.shift
            if user == 'USER'
              puts "Skipping header line" if @debug
              throw :nextline
            end
            pid = psparts.shift
            cputime = psparts.shift
            comms = []
            # The comm field can include spaces, so shift off entries until we
            # hit a day of the week, indicating the start of the lstart field
            while !WDAYS.include?(psparts[0])
              # Don't go into an infinite loop if the line is malformed (shift
              # returns nil when called on an empty array)
              pspart = psparts.shift
              if pspart
                comms << pspart
              else
                warn "Malformed ps line #{line}"
                throw :nextline
              end
            end
            comm = comms.join(' ')
            lstartwday = psparts.shift
            lstartmon  = psparts.shift
            lstartmday = psparts.shift
            lstarttime = psparts.shift
            lstartyear = psparts.shift
            # Whatever is left is the args field
            args = psparts.join(' ')
            puts "user: #{user}, pid: #{pid}, cputime: #{cputime}, comm: #{comm}, lstartwday #{lstartwday}, lstartmon #{lstartmon}, lstartmday #{lstartmday}, lstarttime #{lstarttime}, lstartyear #{lstartyear}, args #{args}" if @debug
            # A zombie can't be doing anything interesting.
            if comm.include?('<defunct>')
              puts "Skipping zombie process #{user}, #{comm}" if @debug
              throw :nextline
            end
            # Skip ignored processes
            if ignored_processes[user]
              ignored_processes[user].each do |igproc|
                if (igproc.kind_of?(Regexp) && comm.match(igproc)) || igproc == comm
                  puts "Skipping ignored process #{user}, #{comm}" if @debug
                  throw :nextline
                end
              end
            end
            # Skip processes of ignored users if configured to do so
            if @ignored_users_processes_ignored &&
               @ignored_users.include?(user) &&
               (user != 'root' || !@keep_root_processes)
              puts "Skipping process of ignored user #{user}, #{comm}" if @debug
              throw :nextline
            end
            # Skip this process
            if pid.to_i == $$
              puts "Skipping this process #{pid}, #{user}, #{args}" if @debug
              throw :nextline
            end
            # Skip our own ps command
            if user == 'root' && args == pscmd
              puts "Skipping our ps process #{user}, #{args}" if @debug
              throw :nextline
            end
            # Parse cputime
            # Format, according to ps(1): [dd-]hh:mm:ss
            cputimesec = 0
            if cputime =~ /^(\d\d)-/
              cpudays = $1
              cputime.sub!(/^\d\d-/, '')
              cputimesec += cpudays.to_i * 24 * 60 * 60
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
          if start < @processthreshtime
            idleness_recent = 25
          else
            idleness_recent = ((Time.now - start) / (Time.now - @processthreshtime) * 25).round
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

