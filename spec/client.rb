#!/usr/bin/env ruby

# How to run the bacon tests:
#   1. Start Riemann on default location 127.0.0.1:5555
#   2. $ bundle exec bacon spec/client.rb

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'riemann'))
require 'riemann/client'
require 'bacon'
require 'set'

Bacon.summary_on_exit

include Riemann

INACTIVITY_TIME = 5
RIEMANN_IP = ENV["RIEMANN_IP"] || "127.0.0.1"
RIEMANN_PORT = ENV["RIEMANN_PORT"] || 5555

def wait_for(&block)
  tries = 0
  while tries < 30
    tries += 1
    res = block.call

    return res unless res.nil?
    sleep(0.1)
  end

  raise "wait_for condition never realized"
end

def roundtrip_metric(m)
  @client_with_transport << {
    :service => 'metric-test',
    :metric => m
  }

  wait_for {@client["service = \"metric-test\" and metric = #{m}"].first }.
    metric.should.equal m
end

def truthy
  lambda { |obj| !(obj.nil? || obj == false) }
end

def falsey
  lambda { |obj| obj.nil? || obj == false }
end

shared "a riemann client" do

  should 'yield itself to given block' do
    client = nil
    Client.new(:host => RIEMANN_IP, :port => RIEMANN_PORT) do |c|
      client = c
    end
    client.should.be.kind_of?(Client)
    client.should.not.be.connected
  end

  should 'close sockets if given a block that raises' do
    client = nil
    begin
      Client.new(:host => RIEMANN_IP, :port => RIEMANN_PORT) do |c|
        client = c
        raise "The Boom"
      end
    rescue
      # swallow the exception
    end
    client.should.be.kind_of?(Client)
    client.should.not.be.connected
  end

  should 'be connected after sending' do
    @client_with_transport.connected?.should.be falsey
    @client.connected?.should.be falsey
    @client_with_transport << {:state => 'ok', :service => 'connected check' }
    @client_with_transport.connected?.should.be truthy
    # NOTE: only single transport connected at this point, @client.connected? is still false until all transports used
  end

  should 'send longs' do
    roundtrip_metric(0)
    roundtrip_metric(-3)
    roundtrip_metric(5)
    roundtrip_metric(-(2**63))
    roundtrip_metric(2**63 - 1)
  end

  should 'send doubles' do
    roundtrip_metric 0.0
    roundtrip_metric 12.0
    roundtrip_metric 1.2300000190734863
  end

  should 'send custom attributes' do
    event = Event.new(
      :service => 'custom',
      :state => 'ok',
      :cats => 'meow',
      :env => 'prod'
    )
    event[:sneak] = 'attack'
    @client_with_transport << event
    event2 = wait_for { @client['service = "custom"'].first }
    event2.service.should.equal 'custom'
    event2.state.should.equal 'ok'
    event2[:cats].should.equal 'meow'
    event2[:env].should.equal 'prod'
    event2[:sneak].should.equal 'attack'
  end

  should 'send a state with a time' do
    t = Time.now.to_i - 10
    @client_with_transport << {
      :state => 'ok',
      :service => 'test',
      :time => t
    }
    wait_for { @client.query('service = "test"').events.first }.time.should.equal t
  end

  should 'send a state without time' do
    @client_with_transport << {
      :state => 'ok',
      :service => 'timeless test'
    }
    wait_for { @client.query('service = "timeless test"').events.first }.time.should.equal Time.now.to_i
  end

  should "query states" do
    @client_with_transport << { :state => 'critical', :service => '1' }
    @client_with_transport << { :state => 'warning', :service => '2' }
    @client_with_transport << { :state => 'critical', :service => '3' }
    @client.query.events.
      map(&:service).to_set.should.superset ['1', '2', '3'].to_set
    @client.query('state = "critical" and (service = "1" or service = "2" or service = "3")').events.
      map(&:service).to_set.should.equal ['1', '3'].to_set
  end

  it '[]' do
#    @client['state = "critical"'].should == []
    @client_with_transport << {:state => 'critical'}
    wait_for { @client['state = "critical"'].first }.state.should.equal 'critical'
  end

  should 'query quickly' do
    t1 = Time.now
    total = 1000
    total.times do |i|
      @client.query('state = "critical"')
    end
    t2 = Time.now

    rate = total / (t2 - t1)
    puts "\n     #{"%.2f" % rate} queries/sec (#{"%.2f" % (1000/rate)}ms per query)"
    rate.should > 100
  end

  should 'be threadsafe' do
    concurrency = 10
    per_thread = 200
    total = concurrency * per_thread

    t1 = Time.now
    (0...concurrency).map do |i|
      Thread.new do
        per_thread.times do
          @client_with_transport.<<({
            :state => 'ok',
            :service => 'test',
            :description => 'desc',
            :metric_f => 1.0
          })
        end
      end
    end.each do |t|
      t.join
    end
    t2 = Time.now

    rate = total / (t2 - t1)
    puts "\n     #{"%.2f" % rate} inserts/sec (#{"%.2f" % (1000/rate)}ms per insert)"
    rate.should > @expected_rate
  end

end


describe "Riemann::Client (TCP transport)" do
  before do
    @client = Client.new(:host => RIEMANN_IP, :port => RIEMANN_PORT)
    @client_with_transport = @client.tcp
    @expected_rate = 100
  end
  behaves_like "a riemann client"

  should 'send a state' do
    res = @client_with_transport << {
      :state => 'ok',
      :service => 'test',
      :description => 'desc',
      :metric_f => 1.0
    }

    res.ok.should.be truthy
    wait_for { @client['service = "test"'].first }.state.should.equal 'ok'
  end

  should 'survive inactivity' do
    @client_with_transport.<<({
      :state => 'warning',
      :service => 'survive TCP inactivity',
    })
    wait_for { @client['service = "survive TCP inactivity"'].first }.state.should.equal 'warning'

    sleep INACTIVITY_TIME

    @client_with_transport.<<({
      :state => 'ok',
      :service => 'survive TCP inactivity',
    }).ok.should.be truthy
    wait_for { @client['service = "survive TCP inactivity"'].first }.state.should.equal 'ok'
  end

  should 'survive local close' do
    @client_with_transport.<<({
      :state => 'warning',
      :service => 'survive TCP local close',
    }).ok.should.be truthy
    wait_for { @client['service = "survive TCP local close"'].first } .state.should.equal 'warning'

    @client.close

    @client_with_transport.<<({
      :state => 'ok',
      :service => 'survive TCP local close',
    }).ok.should.be truthy
    wait_for { @client['service = "survive TCP local close"'].first }.state.should.equal 'ok'
  end
end

describe "Riemann::Client (UDP transport)" do
  before do
    @client = Client.new(:host => RIEMANN_IP, :port => RIEMANN_PORT)
    @client_with_transport = @client.udp
    @expected_rate = 1000
  end
  behaves_like "a riemann client"

  should 'send a state' do
    res = @client_with_transport << {
      :state => 'ok',
      :service => 'test',
      :description => 'desc',
      :metric_f => 1.0
    }

    res.should.be.nil
    wait_for { @client['service = "test"'].first }.state.should.equal 'ok'
  end

  should 'survive inactivity' do
    @client_with_transport.<<({
      :state => 'warning',
      :service => 'survive UDP inactivity',
    })
    wait_for { @client['service = "survive UDP inactivity"'].first } .state.should.equal 'warning'

    sleep INACTIVITY_TIME

    @client_with_transport.<<({
      :state => 'ok',
      :service => 'survive UDP inactivity',
    })
    wait_for { @client['service = "survive UDP inactivity"'].first } .state.should.equal 'ok'
  end

  should 'survive local close' do
    @client_with_transport.<<({
      :state => 'warning',
      :service => 'survive UDP local close',
    })
    wait_for { @client['service = "survive UDP local close"'].first }.state.should.equal 'warning'

    @client.close

    @client_with_transport.<<({
      :state => 'ok',
      :service => 'survive UDP local close',
    })
    wait_for { @client['service = "survive UDP local close"'].first }.state.should.equal 'ok'
  end

  should "raise Riemann::Client::Unsupported exception on query" do
    should.raise(Riemann::Client::Unsupported) { @client_with_transport['service = "test"'] }
    should.raise(Riemann::Client::Unsupported) { @client_with_transport.query('service = "test"') }
  end

end
