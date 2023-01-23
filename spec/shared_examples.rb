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
  it 'is not connected before sending' do
    expect(client).not_to be_connected
  end

  context 'when given a block that raises' do
    let(:client) do
      res = nil
      begin
        Riemann::Client.new(host: 'localhost', port: 5555) do |c|
          res = c
          raise 'The Boom'
        end
      rescue StandardError
        # swallow the exception
      end
      res
    end

    it 'in not connected' do
      expect(client).not_to be_connected
    end
  end

  it 'is connected after sending' do
    client_with_transport << { state: 'ok', service: 'connected check' }
    expect(client_with_transport).to be_connected
    # NOTE: only single transport connected at this point, client.connected? is still false until all transports used
  end

  describe '#<<' do
    subject { wait_for_message_with_id(message_id) }

    let(:message_id) { next_message_id }

    before do
      client_with_transport << {
        state: 'ok',
        service: 'test',
        description: 'desc',
        metric_f: 1.0,
        message_id: message_id
      }
    end

    it 'finds the send message' do
      expect(subject.state).to eq('ok')
    end
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

  context 'when sending custom attributes' do
    subject { wait_for_message_with_id(message_id) }

    before do
      event = Riemann::Event.new(
        service: 'custom',
        state: 'ok',
        cats: 'meow',
        env: 'prod',
        message_id: message_id
      )
      event[:sneak] = 'attack'
      client_with_transport << event
    end

    let(:message_id) { next_message_id }

    it 'has the expected service' do
      expect(subject.service).to eq('custom')
    end

    it 'has the expected state' do
      expect(subject.state).to eq('ok')
    end

    it 'has the expected cats' do
      expect(subject[:cats]).to eq('meow')
    end

    it 'has the expected env' do
      expect(subject[:env]).to eq('prod')
    end

    it 'has the expected sneak' do
      expect(subject[:sneak]).to eq('attack')
    end
  end

  context 'when passing time' do
    subject { wait_for_message_with_id(message_id) }

    before do
      Timecop.freeze
      client_with_transport << {
        state: 'ok',
        service: 'test',
        time: t,
        message_id: message_id
      }
    end

    after do
      Timecop.return
    end

    let(:message_id) { next_message_id }
    let(:t) { (Time.now - 10).to_i }

    it 'has the expected time' do
      expect(subject.time).to eq(t)
    end

    it 'has the expected time_micros' do
      expect(subject.time_micros).to eq(t * 1_000_000)
    end
  end

  context 'when passing time_micros' do
    subject { wait_for_message_with_id(message_id) }

    before do
      Timecop.freeze
      client_with_transport << {
        state: 'ok',
        service: 'test',
        time_micros: t,
        message_id: message_id
      }
    end

    after do
      Timecop.return
    end

    let(:message_id) { next_message_id }
    let(:t) { ((Time.now - 10).to_f * 1_000_000).to_i }

    it 'has the expected time' do
      expect(subject.time).to eq((Time.now - 10).to_i)
    end

    it 'has the expected time_micros' do
      expect(subject.time_micros).to eq(t)
    end
  end

  context 'when passing no time nor time_micros' do
    let(:message_id) { next_message_id }

    let(:time_before) { (Time.now.to_f * 1_000_000).to_i }
    let(:event) do
      client_with_transport << {
        state: 'ok',
        service: 'timeless test',
        message_id: message_id
      }
    end
    let(:time_after) { (Time.now.to_f * 1_000_000).to_i }

    it 'has the expected time_micros' do
      time_before
      event
      time_after

      e = wait_for_message_with_id(message_id)

      expect([time_before, e.time_micros, time_after].sort).to eq([time_before, e.time_micros, time_after])
    end
  end

  describe '#query' do
    before do
      message_id1 = next_message_id
      message_id2 = next_message_id
      message_id3 = next_message_id

      client_with_transport << { state: 'critical', service: '1', message_id: message_id1 }
      client_with_transport << { state: 'warning', service: '2', message_id: message_id2 }
      client_with_transport << { state: 'critical', service: '3', message_id: message_id3 }

      wait_for_message_with_id(message_id3)
    end

    let(:rate) do
      t1 = Time.now
      total = 1000
      total.times do |_i|
        client.query('state = "critical"')
      end
      t2 = Time.now

      total / (t2 - t1)
    end

    it 'returns all events without parameters' do
      expect(client.query.events
            .map(&:service).to_set).to include(%w[1 2 3].to_set)
    end

    it 'returns matched events with parameters' do
      expect(client.query('state = "critical" and (service = "1" or service = "2" or service = "3")').events
            .map(&:service).to_set).to eq(%w[1 3].to_set)
    end

    it 'query quickly' do
      puts "\n     #{format('%.2f', rate)} queries/sec (#{format('%.2f', (1000 / rate))}ms per query)"
      expect(rate).to be > 100
    end
  end

  it '[]' do
    message_id = next_message_id

    #    expect(client['state = "critical"']).to be_empty
    client_with_transport << { state: 'critical', message_id: message_id }
    e = wait_for_message_with_id(message_id)
    expect(e.state).to eq('critical')
  end

  describe '#bulk_send' do
    let(:message_id1) { next_message_id }
    let(:message_id2) { next_message_id }
    let(:event1) { wait_for_message_with_id(message_id1) }
    let(:event2) { wait_for_message_with_id(message_id2) }

    before do
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
    end

    it 'has send the first event' do
      expect(event2.state).to eq('warning')
    end

    it 'has send the second event' do
      expect(event1.state).to eq('ok')
    end
  end

  context 'when using multiple threads' do
    let!(:rate) do
      concurrency = 10
      per_thread = 200
      total = concurrency * per_thread

      t1 = Time.now
      concurrency.times.map do
        Thread.new do
          per_thread.times do
            client_with_transport << {
              state: 'ok',
              service: 'test',
              description: 'desc',
              metric_f: 1.0,
              message_id: next_message_id
            }
          end
        end
      end.each(&:join)
      t2 = Time.now

      total / (t2 - t1)
    end

    it 'is threadsafe' do
      puts "\n     #{format('%.2f', rate)} inserts/sec (#{format('%.2f', (1000 / rate))}ms per insert)"
      expect(rate).to be > expected_rate
    end
  end
end

RSpec.shared_examples 'a riemann client that acknowledge messages' do
  describe '#<<' do
    subject do
      client_with_transport << {
        state: 'ok',
        service: 'test',
        description: 'desc',
        metric_f: 1.0
      }
    end

    it 'acknowledge the message' do
      expect(subject.ok).to be_truthy
    end
  end

  context 'when inactive' do
    let(:message_id1) { next_message_id }
    let(:message1) do
      {
        state: 'warning',
        service: 'survive TCP inactivity',
        message_id: message_id1
      }
    end

    let(:message_id2) { next_message_id }
    let(:message2) do
      {
        state: 'ok',
        service: 'survive TCP inactivity',
        message_id: message_id2
      }
    end

    before do
      client_with_transport << message1
      wait_for_message_with_id(message_id1)
    end

    it 'survive inactivity' do
      sleep INACTIVITY_TIME

      expect((client_with_transport << message2).ok).to be_truthy
      wait_for_message_with_id(message_id2)
    end
  end

  context 'when the connection is closed' do
    let(:message_id1) { next_message_id }
    let(:message1) do
      {
        state: 'warning',
        service: 'survive TCP local close',
        message_id: message_id1
      }
    end

    let(:message_id2) { next_message_id }
    let(:message2) do
      {
        state: 'ok',
        service: 'survive TCP local close',
        message_id: message_id2
      }
    end

    before do
      client_with_transport << message1
      wait_for_message_with_id(message_id1)
    end

    it 'survive local close' do
      client.close

      expect((client_with_transport << message2).ok).to be_truthy
      wait_for_message_with_id(message_id2)
    end
  end
end

RSpec.shared_examples 'a riemann client that does not acknowledge messages' do
  describe '#<<' do
    subject do
      client_with_transport << {
        state: 'ok',
        service: 'test',
        description: 'desc',
        metric_f: 1.0
      }
    end

    it 'does not acknowledge the message' do
      expect(subject).to be_nil
    end
  end

  context 'when inactive' do
    let(:message_id1) { next_message_id }
    let(:message1) do
      {
        state: 'warning',
        service: 'survive UDP inactivity',
        message_id: message_id1
      }
    end

    let(:message_id2) { next_message_id }
    let(:message2) do
      {
        state: 'ok',
        service: 'survive UDP inactivity',
        message_id: message_id2
      }
    end

    before do
      client_with_transport << message1
      wait_for_message_with_id(message_id1)
    end

    it 'survive inactivity' do
      sleep INACTIVITY_TIME

      client_with_transport << message2
      wait_for_message_with_id(message_id2)
    end
  end

  context 'when the connection is closed' do
    let(:message_id1) { next_message_id }
    let(:message1) do
      {
        state: 'warning',
        service: 'survive UDP local close',
        message_id: message_id1
      }
    end

    let(:message_id2) { next_message_id }
    let(:message2) do
      {
        state: 'ok',
        service: 'survive UDP local close',
        message_id: message_id2
      }
    end

    before do
      client_with_transport << message1
      wait_for_message_with_id(message_id1)
    end

    it 'survive local close' do
      client.close

      client_with_transport << message2
      wait_for_message_with_id(message_id2)
    end
  end

  it 'raise Riemann::Client::Unsupported exception on #[]' do
    expect { client_with_transport['service = "test"'] }.to raise_error(Riemann::Client::Unsupported)
  end

  it 'raise Riemann::Client::Unsupported exception on #query' do
    expect { client_with_transport.query('service = "test"') }.to raise_error(Riemann::Client::Unsupported)
  end
end
