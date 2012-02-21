Installing
==========

    gem install reimann-client

Use
===

``` ruby
require 'reimann/client'

# Create a client. Host and port are optional.
c = Reimann::Client.new host: 'localhost', port: 5555

# Send a simple event
c << {service: 'testing', metric: 2.5}

# Or a more complex one
c << {
  host: 'web3',
  service: 'api latency',
  state: 'warn',
  metric: 63.5
  description: "63.5 milliseconds per request"
  time: Time.now.to_i - 10
}

# :host defaults to gethostname(). :time defaults to current unix time. You
# can explicitly override host...

c << {host: nil, service: 'the cloud', state: 'nebulous'}

# Get all the states from the server
c['true']

# Or specific states matching a query
c['host =~ "%.dc1" and (state = "critical" or state = "warning")']

```

Transports
==========

Reimann::Client sends small events over UDP by default, and uses TCP for
queries and large events. UDP sends are essentially "shouting into the void".
They will not block your application and are roughly an order of magnitude
faster than TCP, but you will not know if the server is down or encountered an
error. You can specify what transport to use by selecting a subclient:

``` ruby
c.udp << { :state "ok" } # => nil
c.tcp << { :state "ok" } # => #<Message ...>
c.tcp["true"]            # => [#<Event ... >, ...]
c.udp["true"]            # => raise Reimann::Client::Unsupported
```

Client state management
=======================

Reimann::Client provides some classes to make managing state updates easier.

Reimann::MetricThread starts a thread to poll a metric periodically, which can
be used to flush an accumulated value to ustate at regular intervals.

Reimann::AutoState bundles a state and a client together. Any changes to the
AutoState automatically send the new state to the client.
