##############################################################################
# Idle server agent
# Copyright 2010 AT&T Interactive
# http://idleserver.sourceforge.net/
# License: MIT (http://www.opensource.org/licenses/mit-license.php)
##############################################################################

STDOUT.sync = STDERR.sync = true # All outputs/prompts to the kernel ASAP

require 'uri'            # URI
require 'net/http'       # Net::HTTP
require 'net/https'      # Net::HTTP#use_ssl, etc.

class IdleServer
  VERSION = 'trunk'
  
  class Agent
    def initialize(options={})
      @debug = options[:debug] || false
    end
    
    # Gather all metrics and report them to the server
    def report
      # FIXME
      p recent_logins
    end
    
    def recent_logins
      recents = []
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
          # Ignore the pseudo entries signifying system reboots
          if user == 'reboot' || user == 'shutdown'
            puts "Ignoring pseudo entry for #{user}" if @debug
            next
          end
          if ignored_users.include?(user)
            puts "Ignoring login from ignored user #{user}" if @debug
            next
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
          abort if time.strftime('%a') != wday
          # Now we can finally check and see if this login is recent
          if time >= threshtime
            puts "Login is recent, storing it" if @debug
            recents << line
            if !mostrecent || time > mostrecent
              puts "Login is most recent, updating most recent to #{time}" if @debug
              mostrecent = time
            end
          end
        end
      end
      
      # Calculate idleness
      # The idleness score for recent logins is based on two factors, number
      # of recent logins and the relative recentness of those logins.  I.e.
      # a login today indicates a lower probability of idleness than a login
      # two months ago.
      # Map number of recent logins onto 0..50
      idleness_count = 50
      if recents.size > 0 && recents.size < 10
        idleness_count = 25
      elsif recents.size >= 10
        idleness_count = 0
      end
      puts "Login count is #{recents.size}" if @debug
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
      
      [idleness, recents.join("\n")]
    end
    
    def processes
    end
    
    def cpu
    end
    
    def memory
    end
    
    def network_io
    end
    
    def disk_io
    end
    
  end # class Agent
end # class IdleServer

