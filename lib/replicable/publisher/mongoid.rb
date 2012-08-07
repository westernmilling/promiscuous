require 'replicable/publisher/generic'

class Replicable::Publisher::Mongoid < Replicable::Publisher::Generic
  def operation
    options[:operation]
  end

  def payload
    super.merge(:id => instance.id, :operation => operation)
  end

  def include_attributes?
    operation != :destroy
  end

  def self.publish(options)
    super

    options[:class].class_eval do
      [:create, :update, :destroy].each do |operation|
        __send__("after_#{operation}", "replicable_publish_#{operation}".to_sym)

        define_method "replicable_publish_#{operation}" do
          self.class.replicable_publisher.new(:instance => self, :operation => operation).amqp_publish
        end
      end
    end
  end
end