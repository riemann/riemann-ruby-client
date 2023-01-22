# frozen_string_literal: true

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'riemann'))
require 'riemann/client'
require 'set'
require 'timecop'

include Riemann # rubocop:disable Style/MixinUsage

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

def roundtrip_metric(metric)
  client_with_transport << {
    service: 'metric-test',
    metric: metric
  }

  wait_for { client["service = \"metric-test\" and metric = #{metric}"].first }
    .metric.should eq metric
end

RSpec.shared_examples 'a riemann client' do
  it 'yield itself to given block' do
    client = nil
    Client.new(host: 'localhost', port: 5555) do |c|
      client = c
    end
    client.should be_a(Client)
    client.should_not be_connected
  end

  it 'close sockets if given a block that raises' do
    client = nil
    begin
      Client.new(host: 'localhost', port: 5555) do |c|
        client = c
        raise 'The Boom'
      end
    rescue StandardError
      # swallow the exception
    end
    client.should be_a(Client)
    client.should_not be_connected
  end

  it 'be connected after sending' do
    client_with_transport.connected?.should be_falsey
    client.connected?.should be_falsey
    client_with_transport << { state: 'ok', service: 'connected check' }
    client_with_transport.connected?.should be_truthy
    # NOTE: only single transport connected at this point, client.connected? is still false until all transports used
  end

  it 'send longs' do
    roundtrip_metric(0)
    roundtrip_metric(-3)
    roundtrip_metric(5)
    roundtrip_metric(-(2**63))
    roundtrip_metric(2**63 - 1)
  end

  it 'send doubles' do
    roundtrip_metric 0.0
    roundtrip_metric 12.0
    roundtrip_metric 1.2300000190734863
  end

  it 'send custom attributes' do
    event = Event.new(
      service: 'custom',
      state: 'ok',
      cats: 'meow',
      env: 'prod'
    )
    event[:sneak] = 'attack'
    client_with_transport << event
    event2 = wait_for { client['service = "custom"'].first }
    event2.service.should eq 'custom'
    event2.state.should eq 'ok'
    event2[:cats].should eq 'meow'
    event2[:env].should eq 'prod'
    event2[:sneak].should eq 'attack'
  end

  it 'send a state with a time' do
    Timecop.freeze do
      t = (Time.now - 10).to_i
      client_with_transport << {
        state: 'ok',
        service: 'test',
        time: t
      }
      wait_for { client.query('service = "test"').events.first.time_micros == t * 1_000_000 }
      e = client.query('service = "test"').events.first
      e.time.should eq t
      e.time_micros.should eq t * 1_000_000
    end
  end

  it 'send a state with a time_micros' do
    Timecop.freeze do
      t = ((Time.now - 10).to_f * 1_000_000).to_i
      client_with_transport << {
        state: 'ok',
        service: 'test',
        time_micros: t
      }
      wait_for { client.query('service = "test"').events.first.time_micros == t }
      e = client.query('service = "test"').events.first
      e.time.should eq (Time.now - 10).to_i
      e.time_micros.should eq t
    end
  end

  it 'send a state without time nor time_micros' do
    time_before = (Time.now.to_f * 1_000_000).to_i
    client_with_transport << {
      state: 'ok',
      service: 'timeless test'
    }
    wait_for { client.query('service = "timeless test"').events.first.time_micros >= time_before }
    e = client.query('service = "timeless test"').events.first
    time_after = (Time.now.to_f * 1_000_000).to_i

    [time_before, e.time_micros, time_after].sort.should eq [time_before, e.time_micros, time_after]
  end

  it 'query states' do
    client_with_transport << { state: 'critical', service: '1' }
    client_with_transport << { state: 'warning', service: '2' }
    client_with_transport << { state: 'critical', service: '3' }
    wait_for { client.query('service = "3"').events.first }
    client.query.events
          .map(&:service).to_set.should include %w[1 2 3].to_set
    client.query('state = "critical" and (service = "1" or service = "2" or service = "3")').events
          .map(&:service).to_set.should eq %w[1 3].to_set
  end

  it '[]' do
    #    client['state = "critical"'].should eq []
    client_with_transport << { state: 'critical' }
    wait_for { client['state = "critical"'].first }.state.should eq 'critical'
  end

  it 'query quickly' do
    t1 = Time.now
    total = 1000
    total.times do |_i|
      client.query('state = "critical"')
    end
    t2 = Time.now

    rate = total / (t2 - t1)
    puts "\n     #{format('%.2f', rate)} queries/sec (#{format('%.2f', (1000 / rate))}ms per query)"
    rate.should > 100
  end

  it 'sends bulk events' do
    client_with_transport.bulk_send(
      [
        {
          state: 'ok',
          service: 'foo'
        },
        {
          state: 'warning',
          service: 'bar'
        }
      ]
    )
    wait_for { client['service = "bar"'].first }.state.should eq 'warning'

    e = client['service = "foo"'].first
    e.state.should eq 'ok'
  end

  it 'is threadsafe' do
    concurrency = 10
    per_thread = 200
    total = concurrency * per_thread

    t1 = Time.now
    (0...concurrency).map do |_i|
      Thread.new do
        per_thread.times do
          client_with_transport.<<({
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
    rate.should > expected_rate
  end
end

RSpec.describe 'Riemann::Client' do
  let(:client) do
    Client.new(host: 'localhost', port: 5555)
  end

  let(:expected_rate) { 100 }

  context('with TLS transport') do
    let(:client) do
      Client.new(host: 'localhost', port: 5554, ssl: true,
                 key_file: '/etc/riemann/riemann_server.pkcs8',
                 cert_file: '/etc/riemann/riemann_server.crt',
                 ca_file: '/etc/riemann/riemann_server.crt',
                 ssl_verify: true)
    end
    let(:client_with_transport) { client.tcp }

    it_behaves_like 'a riemann client'

    it 'send a state' do
      res = client_with_transport << {
        state: 'ok',
        service: 'test',
        description: 'desc',
        metric_f: 1.0
      }

      res.ok.should be_truthy
      wait_for { client['service = "test"'].first }.state.should eq 'ok'
    end

    it 'survive inactivity' do
      client_with_transport.<<({
                                 state: 'warning',
                                 service: 'survive TCP inactivity'
                               })
      wait_for { client['service = "survive TCP inactivity"'].first.state == 'warning' }

      sleep INACTIVITY_TIME

      client_with_transport.<<({
                                 state: 'ok',
                                 service: 'survive TCP inactivity'
                               }).ok.should be_truthy
      wait_for { client['service = "survive TCP inactivity"'].first.state == 'ok' }
    end

    it 'survive local close' do
      client_with_transport.<<({
                                 state: 'warning',
                                 service: 'survive TCP local close'
                               }).ok.should be_truthy
      wait_for { client['service = "survive TCP local close"'].first.state == 'warning' }

      client.close

      client_with_transport.<<({
                                 state: 'ok',
                                 service: 'survive TCP local close'
                               }).ok.should be_truthy
      wait_for { client['service = "survive TCP local close"'].first.state == 'ok' }
    end
  end

  context 'with TCP transport' do
    let(:client_with_transport) { client.tcp }

    it_behaves_like 'a riemann client'

    it 'send a state' do
      res = client_with_transport << {
        state: 'ok',
        service: 'test',
        description: 'desc',
        metric_f: 1.0
      }

      res.ok.should be_truthy
      wait_for { client['service = "test"'].first }.state.should eq 'ok'
    end

    it 'survive inactivity' do
      client_with_transport.<<({
                                 state: 'warning',
                                 service: 'survive TCP inactivity'
                               })
      wait_for { client['service = "survive TCP inactivity"'].first.state == 'warning' }

      sleep INACTIVITY_TIME

      client_with_transport.<<({
                                 state: 'ok',
                                 service: 'survive TCP inactivity'
                               }).ok.should be_truthy
      wait_for { client['service = "survive TCP inactivity"'].first.state == 'ok' }
    end

    it 'survive local close' do
      client_with_transport.<<({
                                 state: 'warning',
                                 service: 'survive TCP local close'
                               }).ok.should be_truthy
      wait_for { client['service = "survive TCP local close"'].first.state == 'warning' }

      client.close

      client_with_transport.<<({
                                 state: 'ok',
                                 service: 'survive TCP local close'
                               }).ok.should be_truthy
      wait_for { client['service = "survive TCP local close"'].first.state == 'ok' }
    end
  end

  context('with UDP transport') do
    let(:client_with_transport) { client.udp }
    let(:expected_rate) { 1000 }

    it_behaves_like 'a riemann client'

    it 'send a state' do
      res = client_with_transport << {
        state: 'ok',
        service: 'test',
        description: 'desc',
        metric_f: 1.0
      }

      res.should be_nil
      wait_for { client['service = "test"'].first }.state.should eq 'ok'
    end

    it 'survive inactivity' do
      client_with_transport.<<({
                                 state: 'warning',
                                 service: 'survive UDP inactivity'
                               }).should be_nil
      wait_for { client['service = "survive UDP inactivity"'].first.state == 'warning' }

      sleep INACTIVITY_TIME

      client_with_transport.<<({
                                 state: 'ok',
                                 service: 'survive UDP inactivity'
                               }).should be_nil
      wait_for { client['service = "survive UDP inactivity"'].first.state == 'ok' }
    end

    it 'survive local close' do
      client_with_transport.<<({
                                 state: 'warning',
                                 service: 'survive UDP local close'
                               }).should be_nil
      wait_for { client['service = "survive UDP local close"'].first.state == 'warning' }

      client.close

      client_with_transport.<<({
                                 state: 'ok',
                                 service: 'survive UDP local close'
                               }).should be_nil
      wait_for { client['service = "survive UDP local close"'].first.state == 'ok' }
    end

    it 'raise Riemann::Client::Unsupported exception on query' do
      expect { client_with_transport['service = "test"'] }.to raise_error(Riemann::Client::Unsupported)
      expect { client_with_transport.query('service = "test"') }.to raise_error(Riemann::Client::Unsupported)
    end
  end
end
