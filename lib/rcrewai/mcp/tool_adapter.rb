# frozen_string_literal: true

require_relative '../tools/base'

module RCrewAI
  module MCP
    # Wraps a tool advertised by an MCP server as an RCrewAI::Tools::Base.
    # Names are prefixed with the server name to avoid collisions when an
    # agent has tools from multiple MCP servers.
    class ToolAdapter < RCrewAI::Tools::Base
      def initialize(client, mcp_tool_descriptor, server_name)
        super()
        @client = client
        @descriptor = mcp_tool_descriptor
        @server_name = server_name
        @adapter_name = "#{server_name}__#{mcp_tool_descriptor['name']}"
        @adapter_description = mcp_tool_descriptor['description'].to_s
      end

      def name
        @adapter_name
      end

      def description
        @adapter_description
      end

      def json_schema
        {
          name: @adapter_name,
          description: @adapter_description,
          parameters: stringify_keys(@descriptor['inputSchema'] ||
                                     { 'type' => 'object', 'additionalProperties' => true })
        }
      end

      def execute(**args)
        @client.call_tool(@adapter_name, args)
      end

      def execute_with_validation(args_hash)
        execute(**args_hash.transform_keys(&:to_sym))
      end

      private

      def stringify_keys(value)
        case value
        when Hash
          value.each_with_object({}) { |(k, v), out| out[k.to_s] = stringify_keys(v) }
        when Array
          value.map { |v| stringify_keys(v) }
        else
          value
        end
      end
    end
  end
end
