# frozen_string_literal: true

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'riemann'))
require 'riemann/client'
require 'set'
require 'timecop'

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

  e = wait_for { client["service = \"metric-test\" and metric = #{metric}"].first }
  expect(e.metric).to eq(metric)
end

RSpec.shared_examples 'a riemann client' do
  it 'yield itself to given block' do
    expect(client).to be_a(Riemann::Client)
    expect(client).to_not be_connected
  end

  it 'close sockets if given a block that raises' do
    client = nil
    begin
      Riemann::Client.new(host: 'localhost', port: 5555) do |c|
        client = c
        raise 'The Boom'
      end
    rescue StandardError
      # swallow the exception
    end
    expect(client).to be_a(Riemann::Client)
    expect(client).to_not be_connected
  end

  it 'be connected after sending' do
    expect(client_with_transport.connected?).to be_falsey
    expect(client.connected?).to be_falsey
    client_with_transport << { state: 'ok', service: 'connected check' }
    expect(client_with_transport.connected?).to be_truthy
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
    event = Riemann::Event.new(
      service: 'custom',
      state: 'ok',
      cats: 'meow',
      env: 'prod'
    )
    event[:sneak] = 'attack'
    client_with_transport << event
    event2 = wait_for { client['service = "custom"'].first }
    expect(event2.service).to eq('custom')
    expect(event2.state).to eq('ok')
    expect(event2[:cats]).to eq('meow')
    expect(event2[:env]).to eq('prod')
    expect(event2[:sneak]).to eq('attack')
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
      expect(e.time).to eq(t)
      expect(e.time_micros).to eq(t * 1_000_000)
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
      expect(e.time).to eq((Time.now - 10).to_i)
      expect(e.time_micros).to eq(t)
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

    expect([time_before, e.time_micros, time_after].sort).to eq([time_before, e.time_micros, time_after])
  end

  it 'query states' do
    client_with_transport << { state: 'critical', service: '1' }
    client_with_transport << { state: 'warning', service: '2' }
    client_with_transport << { state: 'critical', service: '3' }
    wait_for { client.query('service = "3"').events.first }
    expect(client.query.events
          .map(&:service).to_set).to include(%w[1 2 3].to_set)
    expect(client.query('state = "critical" and (service = "1" or service = "2" or service = "3")').events
          .map(&:service).to_set).to eq(%w[1 3].to_set)
  end

  it '[]' do
    #    expect(client['state = "critical"']).to be_empty
    client_with_transport << { state: 'critical' }
    e = wait_for { client['state = "critical"'].first }
    expect(e.state).to eq('critical')
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
    expect(rate).to be > 100
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
    e = wait_for { client['service = "bar"'].first }
    expect(e.state).to eq('warning')

    e = client['service = "foo"'].first
    expect(e.state).to eq('ok')
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
    expect(rate).to be > expected_rate
  end
end

RSpec.describe 'Riemann::Client' do
  let(:client) do
    Riemann::Client.new(host: 'localhost', port: 5555)
  end

  let(:expected_rate) { 100 }

  context('with TLS transport') do
    let(:client) do
      Riemann::Client.new(host: 'localhost', port: 5554, ssl: true,
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

      expect(res.ok).to be_truthy
      e = wait_for { client['service = "test"'].first }
      expect(e.state).to eq('ok')
    end

    it 'survive inactivity' do
      client_with_transport.<<({
                                 state: 'warning',
                                 service: 'survive TCP inactivity'
                               })
      wait_for { client['service = "survive TCP inactivity"'].first.state == 'warning' }

      sleep INACTIVITY_TIME

      expect(client_with_transport.<<({
                                        state: 'ok',
                                        service: 'survive TCP inactivity'
                                      }).ok).to be_truthy
      wait_for { client['service = "survive TCP inactivity"'].first.state == 'ok' }
    end

    it 'survive local close' do
      expect(client_with_transport.<<({
                                        state: 'warning',
                                        service: 'survive TCP local close'
                                      }).ok).to be_truthy
      wait_for { client['service = "survive TCP local close"'].first.state == 'warning' }

      client.close

      expect(client_with_transport.<<({
                                        state: 'ok',
                                        service: 'survive TCP local close'
                                      }).ok).to be_truthy
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

      expect(res.ok).to be_truthy
      e = wait_for { client['service = "test"'].first }
      expect(e.state).to eq('ok')
    end

    it 'survive inactivity' do
      client_with_transport.<<({
                                 state: 'warning',
                                 service: 'survive TCP inactivity'
                               })
      wait_for { client['service = "survive TCP inactivity"'].first.state == 'warning' }

      sleep INACTIVITY_TIME

      expect(client_with_transport.<<({
                                        state: 'ok',
                                        service: 'survive TCP inactivity'
                                      }).ok).to be_truthy
      wait_for { client['service = "survive TCP inactivity"'].first.state == 'ok' }
    end

    it 'survive local close' do
      expect(client_with_transport.<<({
                                        state: 'warning',
                                        service: 'survive TCP local close'
                                      }).ok).to be_truthy
      wait_for { client['service = "survive TCP local close"'].first.state == 'warning' }

      client.close

      expect(client_with_transport.<<({
                                        state: 'ok',
                                        service: 'survive TCP local close'
                                      }).ok).to be_truthy
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

      expect(res).to be_nil
      e = wait_for { client['service = "test"'].first }
      expect(e.state).to eq('ok')
    end

    it 'survive inactivity' do
      expect(client_with_transport.<<({
                                        state: 'warning',
                                        service: 'survive UDP inactivity'
                                      })).to be_nil
      wait_for { client['service = "survive UDP inactivity"'].first.state == 'warning' }

      sleep INACTIVITY_TIME

      expect(client_with_transport.<<({
                                        state: 'ok',
                                        service: 'survive UDP inactivity'
                                      })).to be_nil
      wait_for { client['service = "survive UDP inactivity"'].first.state == 'ok' }
    end

    it 'survive local close' do
      expect(client_with_transport.<<({
                                        state: 'warning',
                                        service: 'survive UDP local close'
                                      })).to be_nil
      wait_for { client['service = "survive UDP local close"'].first.state == 'warning' }

      client.close

      expect(client_with_transport.<<({
                                        state: 'ok',
                                        service: 'survive UDP local close'
                                      })).to be_nil
      wait_for { client['service = "survive UDP local close"'].first.state == 'ok' }
    end

    it 'raise Riemann::Client::Unsupported exception on query' do
      expect { client_with_transport['service = "test"'] }.to raise_error(Riemann::Client::Unsupported)
      expect { client_with_transport.query('service = "test"') }.to raise_error(Riemann::Client::Unsupported)
    end
  end
end
