class Promiscuous::Subscriber::Worker::Message
  attr_accessor :payload, :parsed_payload

  def initialize(payload, options={})
    self.payload = payload
    @metadata = options[:metadata]
    @root_worker = options[:root_worker]
  end

  def parsed_payload
    @parsed_payload ||= MultiJson.load(payload)
  end

  def endpoint
    parsed_payload['__amqp__']
  end

  def timestamp
    parsed_payload['timestamp'].to_i
  end

  def dependencies
    return @dependencies if @dependencies
    @dependencies = parsed_payload['dependencies'].try(:symbolize_keys) || {}
    @dependencies[:read]  ||= []
    @dependencies[:write] ||= []
    @dependencies[:read].map!  { |dep| Promiscuous::Dependency.parse(dep) }
    @dependencies[:write].map! { |dep| Promiscuous::Dependency.parse(dep) }
    @dependencies
  end

  def happens_before_dependencies
    return @happens_before_dependencies if @happens_before_dependencies

    deps = []
    deps += dependencies[:read]
    deps += dependencies[:write].map { |dep| dep.dup.tap { |d| d.version -= 1 } }

    # We return the most difficult condition to satisfy first
    @happens_before_dependencies = deps.uniq.reverse
  end

  def has_dependencies?
    return false if Promiscuous::Config.bareback
    dependencies[:read].present? || dependencies[:write].present?
  end

  def to_s
    "#{endpoint} -> #{happens_before_dependencies.join(', ')}"
  end

  def ack
    time = Time.now
    @metadata.ack
    @root_worker.stats.notify_processed_message(self, time)
  rescue Exception => e
    # We don't care if we fail, the message will be redelivered at some point
    Promiscuous.warn "[receive] Some exception happened, but it's okay: #{e}\n#{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.try(:call, e)
  end

  def unit_of_work(type, &block)
    # type is used by the new relic agent, by monkey patching.
    # middleware?
    if defined?(Mongoid)
      Mongoid.unit_of_work { yield }
    else
      yield
    end
  ensure
    if defined?(ActiveRecord)
      ActiveRecord::Base.clear_active_connections!
    end
  end

  def process
    Promiscuous.debug "[receive] #{payload}"
    unit_of_work(endpoint) do
      payload = Promiscuous::Subscriber::Payload.new(parsed_payload, self)
      Promiscuous::Subscriber::Operation.new(payload).commit
    end
    ack
  rescue Promiscuous::Error::AlreadyProcessed => orig_e
    e = Promiscuous::Error::Subscriber.new(orig_e, :payload => payload)
    Promiscuous.debug "[receive] #{e}"
    ack
  rescue Exception => orig_e
    e = Promiscuous::Error::Subscriber.new(orig_e, :payload => payload)
    Promiscuous.warn "[receive] #{e} #{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.try(:call, e)
  end
end
