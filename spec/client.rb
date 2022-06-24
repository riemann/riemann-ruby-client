#!/usr/bin/env ruby
# frozen_string_literal: true

# How to run the bacon tests:
#   1. Start Riemann using the config from riemann.config
#   2. $ bundle exec bacon spec/client.rb

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'riemann'))
require 'riemann/client'
require 'bacon'
require 'set'
require 'timecop'

Bacon.summary_on_exit

include Riemann

INACTIVITY_TIME = 5

def wait_for(&block)
  tries = 0
  while tries < 30
    tries += 1
    begin
      res = block.call
      return res if res
    rescue NoMethodError
      # If a query returns no result (#query retruns nil or #[] returns []),
      # calling #first on it will raise a NoMethodError.  We can ignore it for
      # these tests.
    end
    sleep(0.1)
  end

  raise 'wait_for condition never realized'
end

def roundtrip_metric(m)
  @client_with_transport << {
    service: 'metric-test',
    metric: m
  }

  wait_for { @client["service = \"metric-test\" and metric = #{m}"].first }
    .metric.should.equal m
end

def truthy
  ->(obj) { !(obj.nil? || obj == false) }
end

def falsey
  ->(obj) { obj.nil? || obj == false }
end

shared 'a riemann client' do
  should 'yield itself to given block' do
    client = nil
    Client.new(host: 'localhost', port: 5555) do |c|
      client = c
    end
    client.should.be.is_a?(Client)
    client.should.not.be.connected
  end

  should 'close sockets if given a block that raises' do
    client = nil
    begin
      Client.new(host: 'localhost', port: 5555) do |c|
        client = c
        raise 'The Boom'
      end
    rescue StandardError
      # swallow the exception
    end
    client.should.be.is_a?(Client)
    client.should.not.be.connected
  end

  should 'be connected after sending' do
    @client_with_transport.connected?.should.be falsey
    @client.connected?.should.be falsey
    @client_with_transport << { state: 'ok', service: 'connected check' }
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
      service: 'custom',
      state: 'ok',
      cats: 'meow',
      env: 'prod'
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
    Timecop.freeze do
      t = (Time.now - 10).to_i
      @client_with_transport << {
        state: 'ok',
        service: 'test',
        time: t
      }
      wait_for { @client.query('service = "test"').events.first.time == t }
      e = @client.query('service = "test"').events.first
      e.time.should.equal t
      e.time_micros.should.equal t * 1_000_000
    end
  end

  should 'send a state with a time_micros' do
    Timecop.freeze do
      t = ((Time.now - 10).to_f * 1_000_000).to_i
      @client_with_transport << {
        state: 'ok',
        service: 'test',
        time_micros: t
      }
      wait_for { @client.query('service = "test"').events.first.time_micros == t }
      e = @client.query('service = "test"').events.first
      e.time.should.equal (Time.now - 10).to_i
      e.time_micros.should.equal t
    end
  end

  should 'send a state without time nor time_micros' do
    time_before = (Time.now.to_f * 1_000_000).to_i
    @client_with_transport << {
      state: 'ok',
      service: 'timeless test'
    }
    wait_for { @client.query('service = "timeless test"').events.first.time_micros >= time_before }
    e = @client.query('service = "timeless test"').events.first
    time_after = (Time.now.to_f * 1_000_000).to_i

    [time_before, e.time_micros, time_after].sort.should.equal([time_before, e.time_micros, time_after])
  end

  should 'query states' do
    @client_with_transport << { state: 'critical', service: '1' }
    @client_with_transport << { state: 'warning', service: '2' }
    @client_with_transport << { state: 'critical', service: '3' }
    wait_for { @client.query('service = "3"').events.first }
    @client.query.events
           .map(&:service).to_set.should.superset %w[1 2 3].to_set
    @client.query('state = "critical" and (service = "1" or service = "2" or service = "3")').events
           .map(&:service).to_set.should.equal %w[1 3].to_set
  end

  it '[]' do
    #    @client['state = "critical"'].should == []
    @client_with_transport << { state: 'critical' }
    wait_for { @client['state = "critical"'].first }.state.should.equal 'critical'
  end

  should 'query quickly' do
    t1 = Time.now
    total = 1000
    total.times do |_i|
      @client.query('state = "critical"')
    end
    t2 = Time.now

    rate = total / (t2 - t1)
    puts "\n     #{format('%.2f', rate)} queries/sec (#{format('%.2f', (1000 / rate))}ms per query)"
    rate.should > 100
  end

  should 'be threadsafe' do
    concurrency = 10
    per_thread = 200
    total = concurrency * per_thread

    t1 = Time.now
    (0...concurrency).map do |_i|
      Thread.new do
        per_thread.times do
          @client_with_transport.<<({
                                      state: 'ok',
                                      service: 'test',
                                      description: 'desc',
                                      metric_f: 1.0
                                    })
        end
      end
    end.each(&:join)
    t2 = Time.now

    rate = total / (t2 - t1)
    puts "\n     #{format('%.2f', rate)} inserts/sec (#{format('%.2f', (1000 / rate))}ms per insert)"
    rate.should > @expected_rate
  end
end

describe 'Riemann::Client (TLS transport)' do
  before do
    @client = Client.new(host: 'localhost', port: 5554, ssl: true,
                         key_file: '/etc/riemann/riemann_server.pkcs8',
                         cert_file: '/etc/riemann/riemann_server.crt',
                         ca_file: '/etc/riemann/riemann_server.crt',
                         ssl_verify: true)
    @client_with_transport = @client.tcp
    @expected_rate = 100
  end
  behaves_like 'a riemann client'

  should 'send a state' do
    res = @client_with_transport << {
      state: 'ok',
      service: 'test',
      description: 'desc',
      metric_f: 1.0
    }

    res.ok.should.be truthy
    wait_for { @client['service = "test"'].first }.state.should.equal 'ok'
  end

  should 'survive inactivity' do
    @client_with_transport.<<({
                                state: 'warning',
                                service: 'survive TCP inactivity'
                              })
    wait_for { @client['service = "survive TCP inactivity"'].first.state == 'warning' }

    sleep INACTIVITY_TIME

    @client_with_transport.<<({
                                state: 'ok',
                                service: 'survive TCP inactivity'
                              }).ok.should.be truthy
    wait_for { @client['service = "survive TCP inactivity"'].first.state == 'ok' }
  end

  should 'survive local close' do
    @client_with_transport.<<({
                                state: 'warning',
                                service: 'survive TCP local close'
                              }).ok.should.be truthy
    wait_for { @client['service = "survive TCP local close"'].first.state == 'warning' }

    @client.close

    @client_with_transport.<<({
                                state: 'ok',
                                service: 'survive TCP local close'
                              }).ok.should.be truthy
    wait_for { @client['service = "survive TCP local close"'].first.state == 'ok' }
  end
end

describe 'Riemann::Client (TCP transport)' do
  before do
    @client = Client.new(host: 'localhost', port: 5555)
    @client_with_transport = @client.tcp
    @expected_rate = 100
  end
  behaves_like 'a riemann client'

  should 'send a state' do
    res = @client_with_transport << {
      state: 'ok',
      service: 'test',
      description: 'desc',
      metric_f: 1.0
    }

    res.ok.should.be truthy
    wait_for { @client['service = "test"'].first }.state.should.equal 'ok'
  end

  should 'survive inactivity' do
    @client_with_transport.<<({
                                state: 'warning',
                                service: 'survive TCP inactivity'
                              })
    wait_for { @client['service = "survive TCP inactivity"'].first.state == 'warning' }

    sleep INACTIVITY_TIME

    @client_with_transport.<<({
                                state: 'ok',
                                service: 'survive TCP inactivity'
                              }).ok.should.be truthy
    wait_for { @client['service = "survive TCP inactivity"'].first.state == 'ok' }
  end

  should 'survive local close' do
    @client_with_transport.<<({
                                state: 'warning',
                                service: 'survive TCP local close'
                              }).ok.should.be truthy
    wait_for { @client['service = "survive TCP local close"'].first.state == 'warning' }

    @client.close

    @client_with_transport.<<({
                                state: 'ok',
                                service: 'survive TCP local close'
                              }).ok.should.be truthy
    wait_for { @client['service = "survive TCP local close"'].first.state == 'ok' }
  end
end

describe 'Riemann::Client (UDP transport)' do
  before do
    @client = Client.new(host: 'localhost', port: 5555)
    @client_with_transport = @client.udp
    @expected_rate = 1000
  end
  behaves_like 'a riemann client'

  should 'send a state' do
    res = @client_with_transport << {
      state: 'ok',
      service: 'test',
      description: 'desc',
      metric_f: 1.0
    }

    res.should.be.nil
    wait_for { @client['service = "test"'].first }.state.should.equal 'ok'
  end

  should 'survive inactivity' do
    @client_with_transport.<<({
                                state: 'warning',
                                service: 'survive UDP inactivity'
                              }).should.be.nil
    wait_for { @client['service = "survive UDP inactivity"'].first.state == 'warning' }

    sleep INACTIVITY_TIME

    @client_with_transport.<<({
                                state: 'ok',
                                service: 'survive UDP inactivity'
                              }).should.be.nil
    wait_for { @client['service = "survive UDP inactivity"'].first.state == 'ok' }
  end

  should 'survive local close' do
    @client_with_transport.<<({
                                state: 'warning',
                                service: 'survive UDP local close'
                              }).should.be.nil
    wait_for { @client['service = "survive UDP local close"'].first.state == 'warning' }

    @client.close

    @client_with_transport.<<({
                                state: 'ok',
                                service: 'survive UDP local close'
                              }).should.be.nil
    wait_for { @client['service = "survive UDP local close"'].first.state == 'ok' }
  end

  should 'raise Riemann::Client::Unsupported exception on query' do
    should.raise(Riemann::Client::Unsupported) { @client_with_transport['service = "test"'] }
    should.raise(Riemann::Client::Unsupported) { @client_with_transport.query('service = "test"') }
  end
end
