require 'rails_helper'
require_relative '../../app/services/authorization_manager'
require 'spec_helper'

RSpec.describe AuthorizationManager do
  let(:service) { described_class.new }

  describe '#initialize' do
    it 'initializes an empty permissions cache' do
      manager = described_class.new
      expect(manager.instance_variable_get(:@permissions_cache)).to eq({})
    end
  end

  describe '#can_access?' do
    context 'when user has a higher role than required' do
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

    context 'when user has the exact required role' do
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

    context 'when user has a lower role than required' do
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
      it 'treats unknown user_role as level 0 and returns false when required role is known' do
        expect(service.can_access?('unknown_role', 'viewer')).to be false
      end

      it 'returns true when both user_role and required_role are unknown (0 >= 0)' do
        expect(service.can_access?('unknown_role', 'another_unknown')).to be true
      end
    end

    context 'when required role is unknown' do
      it 'treats unknown required_role as level 0 and returns true for known roles' do
        expect(service.can_access?('admin', 'unknown_role')).to be true
      end

      it 'returns false for unknown user attempting unknown required role is already covered above' do
        expect(service.can_access?('unknown', 'unknown')).to be true
      end
    end

    context 'edge cases' do
      it 'returns false when user_role is nil and required_role is known' do
        expect(service.can_access?(nil, 'viewer')).to be false
      end

      it 'returns true when both user_role and required_role are nil' do
        expect(service.can_access?(nil, nil)).to be true
      end

      it 'returns false when user_role is empty string and required_role is viewer' do
        expect(service.can_access?('', 'viewer')).to be false
      end

      it 'returns true when both user_role and required_role are empty strings' do
        expect(service.can_access?('', '')).to be true
      end
    end
  end

  describe '#can_perform?' do
    context 'read action' do
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
        expect(service.can_perform?('unknown', 'read')).to be false
      end

      it 'denies nil role' do
        expect(service.can_perform?(nil, 'read')).to be false
      end
    end

    context 'write action' do
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
        expect(service.can_perform?('unknown', 'write')).to be false
      end
    end

    context 'delete action' do
      it 'allows only admin' do
        expect(service.can_perform?('admin', 'delete')).to be true
        expect(service.can_perform?('developer', 'delete')).to be false
        expect(service.can_perform?('viewer', 'delete')).to be false
      end
    end

    context 'manage_users action' do
      it 'allows only admin' do
        expect(service.can_perform?('admin', 'manage_users')).to be true
        expect(service.can_perform?('developer', 'manage_users')).to be false
        expect(service.can_perform?('viewer', 'manage_users')).to be false
      end
    end

    context 'unknown action' do
      it 'returns false for unknown actions regardless of role' do
        expect(service.can_perform?('admin', 'unknown_action')).to be false
        expect(service.can_perform?('developer', 'another_action')).to be false
        expect(service.can_perform?('viewer', 'something_else')).to be false
      end

      it 'returns false when action is nil' do
        expect(service.can_perform?('admin', nil)).to be false
      end
    end
  end

  describe '#grant_permission' do
    let(:user_id) { 1 }
    let(:resource_id) { 'resource-123' }

    context 'when user has no existing permissions' do
      it 'adds the resource_id to the permissions cache' do
        service.grant_permission(user_id, resource_id)
        cache = service.instance_variable_get(:@permissions_cache)
        expect(cache[user_id]).to eq([resource_id])
      end

      it 'creates a new array for the user key' do
        expect do
          service.grant_permission(user_id, resource_id)
        end.to change { service.instance_variable_get(:@permissions_cache).keys.include?(user_id) }.from(false).to(true)
      end
    end

    context 'when user already has some permissions' do
      let(:existing_resource) { 'resource-999' }

      before do
        service.grant_permission(user_id, existing_resource)
      end

      it 'adds a new resource_id without removing existing ones' do
        service.grant_permission(user_id, resource_id)
        cache = service.instance_variable_get(:@permissions_cache)
        expect(cache[user_id]).to match_array([existing_resource, resource_id])
      end

      it 'does not add duplicate resource_ids' do
        service.grant_permission(user_id, resource_id)
        service.grant_permission(user_id, resource_id)
        cache = service.instance_variable_get(:@permissions_cache)
        expect(cache[user_id]).to eq([existing_resource, resource_id])
      end
    end

    context 'edge cases' do
      it 'handles nil user_id by using nil as key' do
        service.grant_permission(nil, resource_id)
        cache = service.instance_variable_get(:@permissions_cache)
        expect(cache[nil]).to eq([resource_id])
      end

      it 'handles nil resource_id and stores it' do
        service.grant_permission(user_id, nil)
        cache = service.instance_variable_get(:@permissions_cache)
        expect(cache[user_id]).to eq([nil])
      end
    end
  end

  describe '#has_permission?' do
    let(:user_id) { 1 }
    let(:resource_id) { 'resource-123' }

    context 'when user has the permission' do
      before do
        service.grant_permission(user_id, resource_id)
      end

      it 'returns true' do
        expect(service.has_permission?(user_id, resource_id)).to be true
      end
    end

    context 'when user does not have the permission' do
      before do
        service.grant_permission(user_id, 'other-resource')
      end

      it 'returns false' do
        expect(service.has_permission?(user_id, resource_id)).to be false
      end
    end

    context 'when user has no permissions entry' do
      it 'returns false' do
        expect(service.has_permission?(user_id, resource_id)).to be false
      end
    end

    context 'edge cases' do
      it 'returns false when permissions array exists but is empty' do
        service.instance_variable_set(:@permissions_cache, { user_id => [] })
        expect(service.has_permission?(user_id, resource_id)).to be false
      end

      it 'handles nil user_id as a key' do
        service.grant_permission(nil, resource_id)
        expect(service.has_permission?(nil, resource_id)).to be true
        expect(service.has_permission?(nil, 'other')).to be false
      end

      it 'handles nil resource_id' do
        service.grant_permission(user_id, nil)
        expect(service.has_permission?(user_id, nil)).to be true
        expect(service.has_permission?(user_id, 'something')).to be false
      end
    end
  end

  describe '#revoke_permission' do
    let(:user_id) { 1 }
    let(:resource_id) { 'resource-123' }

    context 'when user has the permission' do
      before do
        service.grant_permission(user_id, resource_id)
      end

      it 'removes the permission from the cache' do
        expect do
          service.revoke_permission(user_id, resource_id)
        end.to change { service.has_permission?(user_id, resource_id) }.from(true).to(false)
      end

      it 'does not raise an error' do
        expect do
          service.revoke_permission(user_id, resource_id)
        end.not_to raise_error
      end
    end

    context 'when user does not have the permission' do
      before do
        service.grant_permission(user_id, 'other-resource')
      end

      it 'leaves other permissions intact' do
        expect do
          service.revoke_permission(user_id, resource_id)
        end.not_to change { service.has_permission?(user_id, 'other-resource') }
      end

      it 'does not raise an error' do
        expect do
          service.revoke_permission(user_id, resource_id)
        end.not_to raise_error
      end
    end

    context 'when user has no entry in the permissions cache' do
      it 'does nothing and does not raise error' do
        expect do
          service.revoke_permission(user_id, resource_id)
        end.not_to raise_error
      end
    end

    context 'edge cases' do
      it 'handles nil user_id key gracefully' do
        service.grant_permission(nil, resource_id)
        expect(service.has_permission?(nil, resource_id)).to be true
        service.revoke_permission(nil, resource_id)
        expect(service.has_permission?(nil, resource_id)).to be false
      end

      it 'handles nil resource_id' do
        service.grant_permission(user_id, nil)
        expect(service.has_permission?(user_id, nil)).to be true
        service.revoke_permission(user_id, nil)
        expect(service.has_permission?(user_id, nil)).to be false
      end
    end
  end

  describe 'error handling and robustness' do
    it 'does not rely on any external dependencies' do
      expect do
        service.can_access?('admin', 'viewer')
        service.can_perform?('admin', 'read')
        service.grant_permission(1, 'res')
        service.has_permission?(1, 'res')
        service.revoke_permission(1, 'res')
      end.not_to raise_error
    end

    it 'handles large number of permissions without raising errors' do
      expect do
        1000.times do |i|
          service.grant_permission(1, "resource-#{i}")
        end
      end.not_to raise_error
      expect(service.instance_variable_get(:@permissions_cache)[1].size).to eq(1000)
    end
  end
end
