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

    context 'when sending a message too large for UDP transport' do
      let(:large_message) do
        {
          data: 'X' * (Riemann::Client::UDP::MAX_SIZE + 10)
        }
      end

      before do
        allow(client.udp).to receive(:send_maybe_recv).and_call_original
        allow(client.tcp).to receive(:send_maybe_recv).and_call_original
        client << large_message
      end

      it 'has tried to send the message using UDP' do
        expect(client.udp).to have_received(:send_maybe_recv)
      end

      it 'has retried to send the message using TCP' do
        expect(client.tcp).to have_received(:send_maybe_recv)
      end
    end
  end
end
