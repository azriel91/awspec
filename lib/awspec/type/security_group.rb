module Awspec::Type
  class SecurityGroup < Base
    aws_resource Aws::EC2::SecurityGroup
    tags_allowed

    def resource_via_client
      @resource_via_client ||= find_security_group(@display_name)
    end

    def id
      @id ||= resource_via_client.group_id if resource_via_client
    end

    def opened?(port = nil, protocol = nil, cidr = nil)
      return inbound_opened?(port, protocol, cidr) if @inbound
      outbound_opened?(port, protocol, cidr)
    end

    def opened_only?(port = nil, protocol = nil, cidr = nil)
      return inbound_opened_only?(port, protocol, cidr) if @inbound
      outbound_opened_only?(port, protocol, cidr)
    end

    def inbound_opened?(port = nil, protocol = nil, cidr = nil)
      resource_via_client.ip_permissions.find do |permission|
        cidr_opened?(permission, cidr) && protocol_opened?(permission, protocol) && port_opened?(permission, port)
      end
    end

    def inbound_opened_only?(port = nil, protocol = nil, cidr = nil)
      permissions = resource_via_client.ip_permissions.select do |permission|
        protocol_opened?(permission, protocol) && port_opened?(permission, port)
      end
      cidrs = []
      permissions.each do |permission|
        permission.ip_ranges.select { |ip_range| cidrs.push(ip_range.cidr_ip) }
      end
      cidrs == Array(cidr)
    end

    def outbound_opened?(port = nil, protocol = nil, cidr = nil)
      resource_via_client.ip_permissions_egress.find do |permission|
        cidr_opened?(permission, cidr) && protocol_opened?(permission, protocol) && port_opened?(permission, port)
      end
    end

    def outbound_opened_only?(port = nil, protocol = nil, cidr = nil)
      permissions = resource_via_client.ip_permissions_egress.select do |permission|
        protocol_opened?(permission, protocol) && port_opened?(permission, port)
      end
      cidrs = []
      permissions.each do |permission|
        permission.ip_ranges.select { |ip_range| cidrs.push(ip_range.cidr_ip) }
      end
      cidrs == Array(cidr)
    end

    def inbound
      @inbound = true
      self
    end

    def outbound
      @inbound = false
      self
    end

    def ip_permissions_count
      resource_via_client.ip_permissions.count
    end
    alias_method :inbound_permissions_count, :ip_permissions_count

    def ip_permissions_egress_count
      resource_via_client.ip_permissions_egress.count
    end
    alias_method :outbound_permissions_count, :ip_permissions_egress_count

    def inbound_rule_count
      resource_via_client.ip_permissions.reduce(0) do |sum, permission|
        sum += permission.ip_ranges.count + permission.user_id_group_pairs.count
      end
    end

    def outbound_rule_count
      resource_via_client.ip_permissions_egress.reduce(0) do |sum, permission|
        sum += permission.ip_ranges.count + permission.user_id_group_pairs.count
      end
    end

    private

    def cidr_opened?(permission, cidr)
      return true unless cidr
      ret = permission.ip_ranges.select do |ip_range|
        ip_range.cidr_ip == cidr
      end
      return true if ret.count > 0
      ret = permission.user_id_group_pairs.select do |sg|
        next true if sg.group_id == cidr
        sg2 = find_security_group(sg.group_id)
        next true if sg2.group_name == cidr
        sg2.tags.find do |tag|
          tag.key == 'Name' && tag.value == cidr
        end
      end
      ret.count > 0
    end

    def protocol_opened?(permission, protocol)
      return true unless protocol
      return false if protocol == 'all' && permission.ip_protocol != '-1'
      return true if permission.ip_protocol == '-1'
      permission.ip_protocol == protocol
    end

    def port_opened?(permission, port)
      return true unless port
      return true unless permission.from_port
      return true unless permission.to_port
      port_between?(port, permission.from_port, permission.to_port)
    end

    def port_between?(port, from_port, to_port)
      if port.is_a?(String) && port.include?('-')
        f, t = port.split('-')
        from_port == f.to_i && to_port == t.to_i
      else
        port.between?(from_port, to_port)
      end
    end
  end
end
