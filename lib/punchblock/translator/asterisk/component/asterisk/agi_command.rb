require 'uri'

module Punchblock
  module Translator
    class Asterisk
      module Component
        module Asterisk
          class AGICommand < Component
            attr_reader :action

            def initialize(component_node, call)
              @component_node, @call = component_node, call
              @id = UUIDTools::UUID.random_create.to_s
              @action = create_action
              pb_logger.debug "Starting up..."
            end

            def execute
              @call.send_ami_action! @action
            end

            def handle_ami_event(event)
              pb_logger.debug "Handling AMI event: #{event.inspect}"
              if event.name == 'AsyncAGI'
                if event['SubEvent'] == 'Exec'
                  pb_logger.debug "Received AsyncAGI:Exec event, sending complete event."
                  send_event complete_event(success_reason(event))
                end
              end
            end

            def parse_agi_result(result)
              match = URI.decode(result).chomp.match(/^(\d{3}) result=(-?\d*) ?(\(?.*\)?)?$/)
              if match
                data = match[3] ? match[3].gsub(/(^\()|(\)$)/, '') : nil
                [match[1].to_i, match[2].to_i, data]
              end
            end

            private

            def create_action
              RubyAMI::Action.new 'AGI', 'Channel' => @call.channel, 'Command' => @component_node.name, 'CommandID' => id do |response|
                handle_response response
              end
            end

            def handle_response(response)
              pb_logger.debug "Handling response: #{response.inspect}"
              case response
              when RubyAMI::Error
                set_node_response false
              when RubyAMI::Response
                set_node_response Ref.new :id => id
              end
            end

            def set_node_response(value)
              pb_logger.debug "Setting response on component node to #{value}"
              @component_node.response = value
            end

            def success_reason(event)
              code, result, data = parse_agi_result event['Result']
              Punchblock::Component::Asterisk::AGI::Command::Complete::Success.new :code => code, :result => result, :data => data
            end

            def complete_event(reason)
              Punchblock::Event::Complete.new.tap do |c|
                c.reason = reason
              end
            end

            def send_event(event)
              event.component_id = id
              pb_logger.debug "Sending event #{event.inspect}"
              @component_node.add_event event
            end
          end
        end
      end
    end
  end
end