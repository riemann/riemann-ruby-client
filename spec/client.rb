#!/usr/bin/env ruby

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'riemann'))
require 'riemann/client'
require 'bacon'
require 'set'

Bacon.summary_on_exit

include Riemann

describe Riemann::Client do
  before do
    @client = Client.new
#    clear
  end

  should 'send a state' do
    res = @client << {
      :state => 'ok',
      :service => 'test',
      :description => 'desc',
      :metric_f => 1.0
    }

    res.should == nil
  end

  def roundtrip_metric(m)
    @client.tcp << {
      :service => 'metric-test',
      :metric => m
    }
    @client["service = \"metric-test\" and metric = #{m}"].
      first.metric.should.equal m
  end

  should 'send longs' do
    roundtrip_metric 0
    roundtrip_metric -3
    roundtrip_metric 5
    roundtrip_metric -(2**63)
    roundtrip_metric(2**63 - 1)
  end

  should 'send doubles' do
    roundtrip_metric 0.0
    roundtrip_metric 12.0
    roundtrip_metric 1.2300000190734863
  end

  should 'send a state with a time' do
    t = Time.now.to_i - 10
    @client.tcp << {
      :state => 'ok',
      :service => 'test',
      :time => t
    }
    @client.query('service = "test"').events.first.time.should == t
  end

  should 'send a state without time' do
    @client.tcp << {
      :state => 'ok',
      :service => 'timeless test'
    }
    @client.query('service = "timeless test"').events.first.time.should == Time.now.to_i
  end

  should "query states" do
    @client << { :state => 'critical', :service => '1' }
    @client << { :state => 'warning', :service => '2' }
    @client << { :state => 'critical', :service => '3' }
    @client.query.events.
      map(&:service).to_set.should.superset ['1', '2', '3'].to_set
    @client.query('state = "critical" and (service = "1" or service = "2" or service = "3")').events.
      map(&:service).to_set.should == ['1', '3'].to_set
  end

  it '[]' do
#    @client['state = "critical"'].should == []
    @client << {:state => 'critical'}
    @client['state = "critical"'].first.state.should == 'critical'
  end

  should 'query quickly' do
    t1 = Time.now
    total = 1000
    total.times do |i|
      @client.query('state = "critical"')
    end
    t2 = Time.now

    rate = total / (t2 - t1)
    puts
    puts "#{rate} queries/sec"
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
          @client.tcp.<<({
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
    puts
    puts "#{rate} inserts/sec"
    rate.should > 100
  end

  should 'survive inactivity' do
    @client.tcp.<<({
      :state => 'warning',
      :service => 'test',
    })

    sleep 5

    @client.tcp.<<({
      :state => 'warning',
      :service => 'test',
    }).ok.should.be.true
  end

  should 'survive local close' do
    @client.tcp.<<({
      :state => 'warning',
      :service => 'test',
    }).ok.should.be.true

    @client.tcp.socket.close

    @client.tcp.<<({
      :state => 'warning',
      :service => 'test',
    }).ok.should.be.true
  end
end
