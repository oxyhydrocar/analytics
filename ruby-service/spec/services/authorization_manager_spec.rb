require 'rails_helper'
require_relative '../../app/services/authorization_manager'
require 'spec_helper'

RSpec.describe AuthorizationManager do
  let(:service) { described_class.new }

  describe '#initialize' do
    it 'initializes an empty permissions cache' do
      instance = described_class.new
      expect(instance.instance_variable_get(:@permissions_cache)).to eq({})
    end
  end

  describe 'ROLE_HIERARCHY' do
    it 'defines admin with highest level' do
      expect(described_class::ROLE_HIERARCHY['admin']).to eq(3)
    end

    it 'defines developer with medium level' do
      expect(described_class::ROLE_HIERARCHY['developer']).to eq(2)
    end

    it 'defines viewer with lowest level' do
      expect(described_class::ROLE_HIERARCHY['viewer']).to eq(1)
    end

    it 'is frozen' do
      expect(described_class::ROLE_HIERARCHY.frozen?).to be true
    end
  end

  describe '#can_access?' do
    context 'when user has higher role than required' do
      it 'returns true for admin accessing developer resources' do
        expect(service.can_access?('admin', 'developer')).to be true
      end

      it 'returns true for admin accessing viewer resources' do
        expect(service.can_access?('admin', 'viewer')).to be true
      end

      it 'returns true for developer accessing viewer resources' do
        expect(service.can_access?('developer', 'viewer')).to be true
      end
    end

    context 'when user has equal role to required' do
      it 'returns true for admin accessing admin resources' do
        expect(service.can_access?('admin', 'admin')).to be true
      end

      it 'returns true for developer accessing developer resources' do
        expect(service.can_access?('developer', 'developer')).to be true
      end

      it 'returns true for viewer accessing viewer resources' do
        expect(service.can_access?('viewer', 'viewer')).to be true
      end
    end

    context 'when user has lower role than required' do
      it 'returns false for developer accessing admin resources' do
        expect(service.can_access?('developer', 'admin')).to be false
      end

      it 'returns false for viewer accessing developer resources' do
        expect(service.can_access?('viewer', 'developer')).to be false
      end

      it 'returns false for viewer accessing admin resources' do
        expect(service.can_access?('viewer', 'admin')).to be false
      end
    end

    context 'when user role is unknown' do
      it 'treats unknown user role as level 0' do
        expect(service.can_access?('unknown_role', 'viewer')).to be false
      end

      it 'returns false when required role is known and user role is nil' do
        expect(service.can_access?(nil, 'viewer')).to be false
      end
    end

    context 'when required role is unknown' do
      it 'treats unknown required role as level 0' do
        expect(service.can_access?('viewer', 'unknown_role')).to be true
      end

      it 'returns true when both roles are unknown' do
        expect(service.can_access?('foo', 'bar')).to be true
      end

      it 'returns true when required role is nil and user is known' do
        expect(service.can_access?('admin', nil)).to be true
      end

      it 'returns true when both roles are nil' do
        expect(service.can_access?(nil, nil)).to be true
      end
    end

    context 'edge cases' do
      it 'handles empty string roles' do
        expect(service.can_access?('', '')).to be true
      end

      it 'handles symbol roles by treating them as unknown' do
        expect(service.can_access?(:admin, :viewer)).to be true
      end
    end
  end

  describe '#can_perform?' do
    context 'when action is read' do
      it 'allows admin' do
        expect(service.can_perform?('admin', 'read')).to be true
      end

      it 'allows developer' do
        expect(service.can_perform?('developer', 'read')).to be true
      end

      it 'allows viewer' do
        expect(service.can_perform?('viewer', 'read')).to be true
      end

      it 'denies unknown role' do
        expect(service.can_perform?('guest', 'read')).to be false
      end

      it 'denies nil role' do
        expect(service.can_perform?(nil, 'read')).to be false
      end
    end

    context 'when action is write' do
      it 'allows admin' do
        expect(service.can_perform?('admin', 'write')).to be true
      end

      it 'allows developer' do
        expect(service.can_perform?('developer', 'write')).to be true
      end

      it 'denies viewer' do
        expect(service.can_perform?('viewer', 'write')).to be false
      end

      it 'denies unknown role' do
        expect(service.can_perform?('guest', 'write')).to be false
      end
    end

    context 'when action is delete' do
      it 'allows admin' do
        expect(service.can_perform?('admin', 'delete')).to be true
      end

      it 'denies developer' do
        expect(service.can_perform?('developer', 'delete')).to be false
      end

      it 'denies viewer' do
        expect(service.can_perform?('viewer', 'delete')).to be false
      end
    end

    context 'when action is manage_users' do
      it 'allows admin' do
        expect(service.can_perform?('admin', 'manage_users')).to be true
      end

      it 'denies developer' do
        expect(service.can_perform?('developer', 'manage_users')).to be false
      end

      it 'denies viewer' do
        expect(service.can_perform?('viewer', 'manage_users')).to be false
      end
    end

    context 'when action is unknown' do
      it 'returns false for admin' do
        expect(service.can_perform?('admin', 'unknown_action')).to be false
      end

      it 'returns false for nil action' do
        expect(service.can_perform?('admin', nil)).to be false
      end

      it 'returns false for empty action' do
        expect(service.can_perform?('admin', '')).to be false
      end
    end
  end

  describe '#grant_permission' do
    let(:user_id) { 1 }
    let(:resource_id) { 'res-123' }

    it 'adds a permission for a new user' do
      service.grant_permission(user_id, resource_id)
      expect(service.has_permission?(user_id, resource_id)).to be true
    end

    it 'does not duplicate permissions for the same resource' do
      2.times do
        service.grant_permission(user_id, resource_id)
      end
      permissions_cache = service.instance_variable_get(:@permissions_cache)
      expect(permissions_cache[user_id].count { |r| r == resource_id }).to eq(1)
    end

    it 'adds multiple resources for the same user' do
      other_resource_id = 'res-456'
      service.grant_permission(user_id, resource_id)
      service.grant_permission(user_id, other_resource_id)
      permissions_cache = service.instance_variable_get(:@permissions_cache)
      expect(permissions_cache[user_id]).to contain_exactly(resource_id, other_resource_id)
    end

    it 'handles different user_ids independently' do
      other_user_id = 2
      service.grant_permission(user_id, resource_id)
      service.grant_permission(other_user_id, resource_id)
      permissions_cache = service.instance_variable_get(:@permissions_cache)
      expect(permissions_cache[user_id]).to eq([resource_id])
      expect(permissions_cache[other_user_id]).to eq([resource_id])
    end

    context 'edge cases' do
      it 'allows nil user_id as a key' do
        service.grant_permission(nil, resource_id)
        permissions_cache = service.instance_variable_get(:@permissions_cache)
        expect(permissions_cache[nil]).to eq([resource_id])
      end

      it 'allows nil resource_id to be added' do
        service.grant_permission(user_id, nil)
        permissions_cache = service.instance_variable_get(:@permissions_cache)
        expect(permissions_cache[user_id]).to eq([nil])
      end
    end
  end

  describe '#has_permission?' do
    let(:user_id) { 1 }
    let(:resource_id) { 'res-123' }

    context 'when permission exists' do
      before do
        service.grant_permission(user_id, resource_id)
      end

      it 'returns true' do
        expect(service.has_permission?(user_id, resource_id)).to be true
      end
    end

    context 'when permission does not exist for user' do
      before do
        service.grant_permission(user_id, 'other-resource')
      end

      it 'returns false' do
        expect(service.has_permission?(user_id, resource_id)).to be false
      end
    end

    context 'when user has no permissions' do
      it 'returns false' do
        expect(service.has_permission?(user_id, resource_id)).to be false
      end
    end

    context 'when user_id is unknown' do
      it 'returns false' do
        expect(service.has_permission?(999, resource_id)).to be false
      end
    end

    context 'edge cases' do
      it 'returns false when resource_id is nil and not present' do
        service.grant_permission(user_id, resource_id)
        expect(service.has_permission?(user_id, nil)).to be false
      end

      it 'returns true when resource_id is nil and present' do
        service.grant_permission(user_id, nil)
        expect(service.has_permission?(user_id, nil)).to be true
      end
    end
  end

  describe '#revoke_permission' do
    let(:user_id) { 1 }
    let(:resource_id) { 'res-123' }
    let(:other_resource_id) { 'res-456' }

    context 'when permission exists' do
      before do
        service.grant_permission(user_id, resource_id)
      end

      it 'removes the permission' do
        expect do
          service.revoke_permission(user_id, resource_id)
        end.not_to raise_error
        expect(service.has_permission?(user_id, resource_id)).to be false
      end

      it 'does not affect other permissions for the same user' do
        service.grant_permission(user_id, other_resource_id)
        service.revoke_permission(user_id, resource_id)
        expect(service.has_permission?(user_id, other_resource_id)).to be true
      end
    end

    context 'when permission does not exist' do
      it 'does not raise an error' do
        expect do
          service.revoke_permission(user_id, resource_id)
        end.not_to raise_error
      end

      it 'leaves permissions_cache unchanged for other users' do
        other_user_id = 2
        service.grant_permission(other_user_id, resource_id)
        service.revoke_permission(user_id, resource_id)
        expect(service.has_permission?(other_user_id, resource_id)).to be true
      end
    end

    context 'when user has no permissions at all' do
      it 'does not initialize permissions for the user' do
        service.revoke_permission(user_id, resource_id)
        permissions_cache = service.instance_variable_get(:@permissions_cache)
        expect(permissions_cache[user_id]).to be_nil
      end
    end

    context 'edge cases' do
      it 'handles nil user_id gracefully' do
        service.grant_permission(nil, resource_id)
        expect do
          service.revoke_permission(nil, resource_id)
        end.not_to raise_error
        expect(service.has_permission?(nil, resource_id)).to be false
      end

      it 'handles nil resource_id gracefully' do
        service.grant_permission(user_id, nil)
        expect do
          service.revoke_permission(user_id, nil)
        end.not_to raise_error
        expect(service.has_permission?(user_id, nil)).to be false
      end
    end
  end
end
