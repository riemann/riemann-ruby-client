# frozen_string_literal: true

RSpec.configure do |config|
  # Limits the available syntax to the non-monkey patched syntax that is
  # recommended. For more details, see:
  # https://relishapp.com/rspec/rspec-core/docs/configuration/zero-monkey-patching-mode
  # config.disable_monkey_patching!

  # This setting enables warnings. It's recommended, but in some cases may
  # be too noisy due to issues in dependencies.
  config.warnings = true

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = :random

  # Seed global randomization in this process using the `--seed` CLI option.
  # Setting this allows you to use `--seed` to deterministically reproduce
  # test failures related to randomization by passing the same `--seed` value
  # as the one that triggered the failure.
  Kernel.srand config.seed

  # RSpec tries to be friendly to us by detecting deadlocks but this breaks CI
  # :-(
  #
  # Some tests want to start multiple thread in a let block, and this
  # thread-safety mechanism makes it impossible and raise an exception while
  # our code is working correctly.
  #
  # This issue seems the same as:
  # https://github.com/rspec/rspec-core/issues/2064
  #
  # The feature we disable was introduced in:
  # https://github.com/rspec/rspec-core/commit/ffe00a1d4e369e312881e6b2c091c8b6fb7e6087
  config.threadsafe = false
end
