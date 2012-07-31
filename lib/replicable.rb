require 'active_support/core_ext'
require 'replicable/primary'

module Replicable
  mattr_reader :mongoid3
  @@mongoid3 = Gem.loaded_specs['mongoid'].version >= Gem::Version.new('3.0.0')
end
