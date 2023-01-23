# frozen_string_literal: true

require 'riemann'
require 'riemann/client'
require 'set'
require 'timecop'

INACTIVITY_TIME = 5

class Sequence
  include Singleton

  def initialize
    @nextval = 0
  end

  def nextval
    @nextval += 1
  end

  def current
    @nextval
  end
end

def next_message_id
  Sequence.instance.nextval
  "#{Process.pid}-#{Sequence.instance.current}"
end

def wait_for_message_with_id(message_id)
  wait_for { client[%(message_id = "#{message_id}")].first }
end

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
  message_id = next_message_id

  client_with_transport << {
    service: 'metric-test',
    metric: metric,
    message_id: message_id
  }

  e = wait_for_message_with_id(message_id)
  expect(e.metric).to eq(metric)
end

RSpec.shared_examples 'a riemann client' do
  it 'yield itself to given block' do
    expect(client).to be_a(Riemann::Client)
    expect(client).not_to be_connected
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
    expect(client).not_to be_connected
  end

  it 'be connected after sending' do
    expect(client_with_transport).not_to be_connected
    expect(client).not_to be_connected
    client_with_transport << { state: 'ok', service: 'connected check' }
    expect(client_with_transport).to be_connected
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
    message_id = next_message_id

    event = Riemann::Event.new(
      service: 'custom',
      state: 'ok',
      cats: 'meow',
      env: 'prod',
      message_id: message_id
    )
    event[:sneak] = 'attack'
    client_with_transport << event
    event2 = wait_for_message_with_id(message_id)
    expect(event2.service).to eq('custom')
    expect(event2.state).to eq('ok')
    expect(event2[:cats]).to eq('meow')
    expect(event2[:env]).to eq('prod')
    expect(event2[:sneak]).to eq('attack')
  end

  it 'send a state with a time' do
    Timecop.freeze do
      message_id = next_message_id

      t = (Time.now - 10).to_i
      client_with_transport << {
        state: 'ok',
        service: 'test',
        time: t,
        message_id: message_id
      }
      wait_for_message_with_id(message_id)
      e = client.query('service = "test"').events.first
      expect(e.time).to eq(t)
      expect(e.time_micros).to eq(t * 1_000_000)
    end
  end

  it 'send a state with a time_micros' do
    Timecop.freeze do
      message_id = next_message_id

      t = ((Time.now - 10).to_f * 1_000_000).to_i
      client_with_transport << {
        state: 'ok',
        service: 'test',
        time_micros: t,
        message_id: message_id
      }
      wait_for_message_with_id(message_id)
      e = client.query('service = "test"').events.first
      expect(e.time).to eq((Time.now - 10).to_i)
      expect(e.time_micros).to eq(t)
    end
  end

  it 'send a state without time nor time_micros' do
    message_id = next_message_id

    time_before = (Time.now.to_f * 1_000_000).to_i
    client_with_transport << {
      state: 'ok',
      service: 'timeless test',
      message_id: message_id
    }
    e = wait_for_message_with_id(message_id)
    time_after = (Time.now.to_f * 1_000_000).to_i

    expect([time_before, e.time_micros, time_after].sort).to eq([time_before, e.time_micros, time_after])
  end

  it 'query states' do
    message_id1 = next_message_id
    message_id2 = next_message_id
    message_id3 = next_message_id

    client_with_transport << { state: 'critical', service: '1', message_id: message_id1 }
    client_with_transport << { state: 'warning', service: '2', message_id: message_id2 }
    client_with_transport << { state: 'critical', service: '3', message_id: message_id3 }
    wait_for_message_with_id(message_id3)
    expect(client.query.events
          .map(&:service).to_set).to include(%w[1 2 3].to_set)
    expect(client.query('state = "critical" and (service = "1" or service = "2" or service = "3")').events
          .map(&:service).to_set).to eq(%w[1 3].to_set)
  end

  it '[]' do
    message_id = next_message_id

    #    expect(client['state = "critical"']).to be_empty
    client_with_transport << { state: 'critical', message_id: message_id }
    e = wait_for_message_with_id(message_id)
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
    message_id1 = next_message_id
    message_id2 = next_message_id

    client_with_transport.bulk_send(
      [
        {
          state: 'ok',
          service: 'foo',
          message_id: message_id1
        },
        {
          state: 'warning',
          service: 'bar',
          message_id: message_id2
        }
      ]
    )
    wait_for_message_with_id(message_id2)

    e = client['service = "bar"'].first
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
                                     metric_f: 1.0,
                                     message_id: next_message_id
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

RSpec.shared_examples 'a riemann client that acknowledge messages' do
  it 'send a state' do
    message_id = next_message_id

    res = client_with_transport << {
      state: 'ok',
      service: 'test',
      description: 'desc',
      metric_f: 1.0,
      message_id: message_id
    }

    expect(res.ok).to be_truthy
    e = wait_for_message_with_id(message_id)
    expect(e.state).to eq('ok')
  end

  it 'survive inactivity' do
    message_id = next_message_id

    client_with_transport.<<({
                               state: 'warning',
                               service: 'survive TCP inactivity',
                               message_id: message_id
                             })
    wait_for_message_with_id(message_id)

    sleep INACTIVITY_TIME

    message_id = next_message_id

    expect(client_with_transport.<<({
                                      state: 'ok',
                                      service: 'survive TCP inactivity',
                                      message_id: message_id
                                    }).ok).to be_truthy
    wait_for_message_with_id(message_id)
  end

  it 'survive local close' do
    message_id = next_message_id

    expect(client_with_transport.<<({
                                      state: 'warning',
                                      service: 'survive TCP local close',
                                      message_id: message_id
                                    }).ok).to be_truthy
    wait_for_message_with_id(message_id)

    client.close

    message_id = next_message_id

    expect(client_with_transport.<<({
                                      state: 'ok',
                                      service: 'survive TCP local close',
                                      message_id: message_id
                                    }).ok).to be_truthy
    wait_for_message_with_id(message_id)
  end
end

RSpec.shared_examples 'a riemann client that does not acknowledge messages' do
  it 'send a state' do
    message_id = next_message_id

    res = client_with_transport << {
      state: 'ok',
      service: 'test',
      description: 'desc',
      metric_f: 1.0,
      message_id: message_id
    }

    expect(res).to be_nil
    e = wait_for_message_with_id(message_id)
    expect(e.state).to eq('ok')
  end

  it 'survive inactivity' do
    message_id = next_message_id

    expect(client_with_transport.<<({
                                      state: 'warning',
                                      service: 'survive UDP inactivity',
                                      message_id: message_id
                                    })).to be_nil
    wait_for_message_with_id(message_id)

    sleep INACTIVITY_TIME

    message_id = next_message_id

    expect(client_with_transport.<<({
                                      state: 'ok',
                                      service: 'survive UDP inactivity',
                                      message_id: message_id
                                    })).to be_nil
    wait_for_message_with_id(message_id)
  end

  it 'survive local close' do
    message_id = next_message_id

    expect(client_with_transport.<<({
                                      state: 'warning',
                                      service: 'survive UDP local close',
                                      message_id: message_id
                                    })).to be_nil
    wait_for_message_with_id(message_id)

    client.close

    message_id = next_message_id

    expect(client_with_transport.<<({
                                      state: 'ok',
                                      service: 'survive UDP local close',
                                      message_id: message_id
                                    })).to be_nil
    wait_for_message_with_id(message_id)
  end

  it 'raise Riemann::Client::Unsupported exception on query' do
    expect { client_with_transport['service = "test"'] }.to raise_error(Riemann::Client::Unsupported)
    expect { client_with_transport.query('service = "test"') }.to raise_error(Riemann::Client::Unsupported)
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
    it_behaves_like 'a riemann client that acknowledge messages'
  end

  context 'with TCP transport' do
    let(:client_with_transport) { client.tcp }

    it_behaves_like 'a riemann client'
    it_behaves_like 'a riemann client that acknowledge messages'
  end

  context('with UDP transport') do
    let(:client_with_transport) { client.udp }
    let(:expected_rate) { 1000 }

    it_behaves_like 'a riemann client'
    it_behaves_like 'a riemann client that does not acknowledge messages'
  end
end
