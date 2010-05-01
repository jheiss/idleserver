require 'test/unit'
require 'idleserver'

# Give ourself access to some Agent variables
class IdleServer
  class Agent
    attr_reader :debug
  end
end

class AgentTests < Test::Unit::TestCase
  def test_help
    output = nil
    # The File.join(blah) is roughly equivalent to '../bin/idleserver'
    parentdir = File.dirname(File.dirname(__FILE__))
    IO.popen("ruby #{File.join(parentdir, 'bin', 'idleserver')} --help") do |pipe|
      output = pipe.readlines
    end
    # Make sure at least something resembling help output is there
    assert(output.any? {|line| line.include?('Usage: idleserver')}, 'help output content')
    # Make sure it fits on the screen
    assert(output.all? {|line| line.length <= 80}, 'help output columns')
    assert(output.size <= 23, 'help output lines')
  end
  
  def test_initialize
    idleagent = IdleServer::Agent.new(:debug => true)
    assert_equal(true, idleagent.debug)
    idleagent = IdleServer::Agent.new(:debug => false)
    assert_equal(false, idleagent.debug)
    idleagent = IdleServer::Agent.new
    assert_equal(false, idleagent.debug)
  end
  
  def test_logins
    idleagent = IdleServer::Agent.new
    logins = idleagent.logins
    assert_equal('logins', logins[:name])
    assert_operator(logins[:idleness], :>=, 0)
    assert_operator(logins[:idleness], :<=, 100)
    assert_kind_of(String, logins[:message])
  end
  
  def test_processes
    idleagent = IdleServer::Agent.new
    processes = idleagent.processes
    assert_equal('processes', processes[:name])
    assert_operator(processes[:idleness], :>=, 0)
    assert_operator(processes[:idleness], :<=, 100)
    assert_kind_of(String, processes[:message])
  end
  
end

