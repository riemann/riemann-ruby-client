# frozen_string_literal: true

require 'riemann'
require 'riemann/client'

require 'spec_helper'
require 'shared_examples'

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
