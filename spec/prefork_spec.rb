
require File.join(File.dirname(__FILE__), %w[spec_helper])
require 'tempfile'
require 'fileutils'
require 'enumerator'

if Servolux.fork?

describe Servolux::Prefork do

  def pids
    workers.map! { |w| w.instance_variable_get(:@piper).pid }
  end

  def workers
    ary = []
    return ary if @prefork.nil?
    @prefork.each_worker { |w| ary << w }
    ary
  end

  def worker_count
    Dir.glob(@glob).length
  end

  def alive?( pid )
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH, Errno::ENOENT
    false
  end

  before :all do
    tmp = Tempfile.new 'servolux-prefork'
    @path = path = tmp.path; tmp.unlink
    @glob = @path + '/*.txt'
    FileUtils.mkdir @path

    @worker = Module.new {
      define_method(:before_executing) { @fd = File.open(path + "/#$$.txt", 'w') }
      def after_executing() @fd.close; FileUtils.rm_f @fd.path; end
      def execute() @fd.puts Time.now; sleep 2; end
      def hup() @thread.wakeup; end
      alias :term :hup
    }
  end

  after :all do
    FileUtils.rm_rf @path
  end

  before :each do
    @prefork = nil
    FileUtils.rm_f "#@path/*.txt"
  end

  after :each do
    next if @prefork.nil?
    @prefork.stop
    @prefork.each_worker { |worker| worker.signal('KILL') }
    @prefork = nil
    FileUtils.rm_f "#@path/*.txt"
  end

  it "starts up a single worker" do
    @prefork = Servolux::Prefork.new :module => @worker
    @prefork.start 1
    ary = workers
    sleep 0.1 until ary.all? { |w| w.alive? }
    sleep 0.1 until worker_count >= 1

    ary = Dir.glob(@glob)
    ary.length.should == 1
    File.basename(ary.first).to_i.should == pids.first
  end

  it "starts up a number of workers" do
    @prefork = Servolux::Prefork.new :module => @worker
    @prefork.start 8
    ary = workers
    sleep 0.250 until ary.all? { |w| w.alive? }
    sleep 0.250 until worker_count >= 8

    ary = Dir.glob(@glob)
    ary.length.should == 8

    ary.map! { |fn| File.basename(fn).to_i }.sort!
    ary.should == pids.sort
  end

  it "stops workers gracefullly" do
    @prefork = Servolux::Prefork.new :module => @worker
    @prefork.start 3
    ary = workers
    sleep 0.250 until ary.all? { |w| w.alive? }
    sleep 0.250 until worker_count >= 3

    ary = Dir.glob(@glob)
    ary.length.should == 3

    @prefork.stop
    sleep 0.250 until Dir.glob(@glob).length == 0

    rv = workers.all? { |w| !w.alive? }
    rv.should == true
  end

  it "restarts a worker via SIGHUP" do
    @prefork = Servolux::Prefork.new :module => @worker
    @prefork.start 2
    ary = workers
    sleep 0.250 until ary.all? { |w| w.alive? }
    sleep 0.250 until worker_count >= 2

    pid = pids.last
    ary.last.signal 'HUP'
    @prefork.reap until !alive? pid
    sleep 0.250 until ary.all? { |w| w.alive? }

    pid.should_not == pids.last
  end

end
end  # Servolux.fork?

