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
    IO.popen("ruby -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'idleserver')} --help") do |pipe|
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
end

