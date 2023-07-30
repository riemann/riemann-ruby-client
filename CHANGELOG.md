# Changelog

## [v1.2.1](https://github.com/riemann/riemann-ruby-client/tree/v1.2.1) (2023-07-30)

[Full Changelog](https://github.com/riemann/riemann-ruby-client/compare/v1.2.0...v1.2.1)

**Fixed bugs:**

- Fix sending large batch of events over TLS [\#51](https://github.com/riemann/riemann-ruby-client/pull/51) ([smortex](https://github.com/smortex))

## [v1.2.0](https://github.com/riemann/riemann-ruby-client/tree/v1.2.0) (2023-06-28)

[Full Changelog](https://github.com/riemann/riemann-ruby-client/compare/v1.1.0...v1.2.0)

**Implemented enhancements:**

- Allow connection to Riemann using TLS 1.3 [\#49](https://github.com/riemann/riemann-ruby-client/pull/49) ([smortex](https://github.com/smortex))

## [v1.1.0](https://github.com/riemann/riemann-ruby-client/tree/v1.1.0) (2023-01-23)

[Full Changelog](https://github.com/riemann/riemann-ruby-client/compare/v1.0.1...v1.1.0)

**Implemented enhancements:**

- Add support for sending events in bulk [\#44](https://github.com/riemann/riemann-ruby-client/pull/44) ([smortex](https://github.com/smortex))

**Fixed bugs:**

- Fix UDP fallback to TCP on large messages [\#46](https://github.com/riemann/riemann-ruby-client/pull/46) ([smortex](https://github.com/smortex))

**Merged pull requests:**

- Modernize unit tests [\#45](https://github.com/riemann/riemann-ruby-client/pull/45) ([smortex](https://github.com/smortex))
- Switch from Bacon to RSpec [\#43](https://github.com/riemann/riemann-ruby-client/pull/43) ([smortex](https://github.com/smortex))
- Create codeql-analysis.yml [\#40](https://github.com/riemann/riemann-ruby-client/pull/40) ([jamtur01](https://github.com/jamtur01))

## [v1.0.1](https://github.com/riemann/riemann-ruby-client/tree/v1.0.1) (2022-06-25)

[Full Changelog](https://github.com/riemann/riemann-ruby-client/compare/v1.0.0...v1.0.1)

**Merged pull requests:**

- Setup Rubocop and lower required Ruby version [\#37](https://github.com/riemann/riemann-ruby-client/pull/37) ([smortex](https://github.com/smortex))

## [v1.0.0](https://github.com/riemann/riemann-ruby-client/tree/v1.0.0) (2022-06-16)

[Full Changelog](https://github.com/riemann/riemann-ruby-client/compare/0.2.6...v1.0.0)

**Implemented enhancements:**

- Add support for micro-seconds resolution [\#34](https://github.com/riemann/riemann-ruby-client/pull/34) ([smortex](https://github.com/smortex))
- Add support for TLS [\#33](https://github.com/riemann/riemann-ruby-client/pull/33) ([smortex](https://github.com/smortex))
- Add support for IPv6 addresses [\#30](https://github.com/riemann/riemann-ruby-client/pull/30) ([dch](https://github.com/dch))

**Merged pull requests:**

- Fix race conditions in CI [\#35](https://github.com/riemann/riemann-ruby-client/pull/35) ([smortex](https://github.com/smortex))
- Modernize and setup CI [\#32](https://github.com/riemann/riemann-ruby-client/pull/32) ([smortex](https://github.com/smortex))
- Bump beefcake dependency [\#29](https://github.com/riemann/riemann-ruby-client/pull/29) ([dch](https://github.com/dch))

## [0.2.6](https://github.com/riemann/riemann-ruby-client/tree/0.2.6) (2015-11-18)

[Full Changelog](https://github.com/riemann/riemann-ruby-client/compare/0.2.5...0.2.6)

**Merged pull requests:**

- Client should yield self [\#22](https://github.com/riemann/riemann-ruby-client/pull/22) ([agile](https://github.com/agile))
- Allow TCP sockets to work on Windows [\#21](https://github.com/riemann/riemann-ruby-client/pull/21) ([sgran](https://github.com/sgran))
- README hash syntax fix [\#20](https://github.com/riemann/riemann-ruby-client/pull/20) ([squarism](https://github.com/squarism))

## [0.2.5](https://github.com/riemann/riemann-ruby-client/tree/0.2.5) (2015-02-05)

[Full Changelog](https://github.com/riemann/riemann-ruby-client/compare/0.2.4...0.2.5)

## [0.2.4](https://github.com/riemann/riemann-ruby-client/tree/0.2.4) (2015-02-03)

[Full Changelog](https://github.com/riemann/riemann-ruby-client/compare/0.2.2...0.2.4)

**Merged pull requests:**

- Tightening beefcake requirement [\#19](https://github.com/riemann/riemann-ruby-client/pull/19) ([aphyr](https://github.com/aphyr))
- Fix for \#17, plus test and connection refactor [\#18](https://github.com/riemann/riemann-ruby-client/pull/18) ([RKelln](https://github.com/RKelln))
- Ensure that we close the connection if we got an error back [\#16](https://github.com/riemann/riemann-ruby-client/pull/16) ([eric](https://github.com/eric))
- String\#clear doesn't exist in 1.8 [\#15](https://github.com/riemann/riemann-ruby-client/pull/15) ([eric](https://github.com/eric))
- Tcp client with timeouts [\#14](https://github.com/riemann/riemann-ruby-client/pull/14) ([eric](https://github.com/eric))

## [0.2.2](https://github.com/riemann/riemann-ruby-client/tree/0.2.2) (2013-05-28)

[Full Changelog](https://github.com/riemann/riemann-ruby-client/compare/0.2.0...0.2.2)

**Merged pull requests:**

- Update README with timeout information [\#11](https://github.com/riemann/riemann-ruby-client/pull/11) ([gsandie](https://github.com/gsandie))
- Add tcp socket timeouts [\#10](https://github.com/riemann/riemann-ruby-client/pull/10) ([gsandie](https://github.com/gsandie))
- Socket can not be opened in method connected? [\#9](https://github.com/riemann/riemann-ruby-client/pull/9) ([vadv](https://github.com/vadv))

## [0.2.0](https://github.com/riemann/riemann-ruby-client/tree/0.2.0) (2013-04-02)

[Full Changelog](https://github.com/riemann/riemann-ruby-client/compare/version-0.0.7...0.2.0)

**Merged pull requests:**

- Get and set attributes using hash-style accessors [\#8](https://github.com/riemann/riemann-ruby-client/pull/8) ([jegt](https://github.com/jegt))
- Add extra attributes added to the Event constructor to the event as Attribute instances [\#7](https://github.com/riemann/riemann-ruby-client/pull/7) ([jegt](https://github.com/jegt))
- Change attribute name to attribute key [\#6](https://github.com/riemann/riemann-ruby-client/pull/6) ([b](https://github.com/b))
- Arbitrary attributes on events [\#5](https://github.com/riemann/riemann-ruby-client/pull/5) ([b](https://github.com/b))

## [version-0.0.7](https://github.com/riemann/riemann-ruby-client/tree/version-0.0.7) (2012-04-16)

[Full Changelog](https://github.com/riemann/riemann-ruby-client/compare/fe25a3b01681612defc39250006748069e06a172...version-0.0.7)

**Merged pull requests:**

- Add support for ruby 1.8 [\#1](https://github.com/riemann/riemann-ruby-client/pull/1) ([eric](https://github.com/eric))



\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
