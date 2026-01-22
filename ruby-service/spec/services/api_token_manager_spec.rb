require 'rails_helper'
require_relative '../../app/services/api_token_manager'
require 'spec_helper'

RSpec.describe ApiTokenManager do
  subject(:manager) do
    described_class.new
  end

  describe '#initialize' do
    it 'initializes with an empty token store' do
      manager_instance = described_class.new
      tokens_instance_variable = manager_instance.instance_variable_get(:@tokens)
      expect(tokens_instance_variable).to eq({})
    end
  end

  describe '#generate_token' do
    let(:user_id) do
      123
    end

    let(:scope) do
      'read'
    end

    let(:fixed_time) do
      Time.now
    end

    before do
      allow(Time).to receive(:now).and_return(fixed_time)
      allow(SecureRandom).to receive(:urlsafe_base64).and_return('fixed-token')
    end

    it 'returns a token string' do
      token = manager.generate_token(user_id, scope: scope)
      expect(token).to be_a(String)
      expect(token).to eq('fixed-token')
    end

    it 'stores token data with correct user_id and scope' do
      token = manager.generate_token(user_id, scope: 'write')
      tokens = manager.instance_variable_get(:@tokens)
      expect(tokens[token]).to be_a(Hash)
      expect(tokens[token][:user_id]).to eq(user_id)
      expect(tokens[token][:scope]).to eq('write')
    end

    it 'stores created_at and last_used timestamps' do
      token = manager.generate_token(user_id, scope: scope)
      tokens = manager.instance_variable_get(:@tokens)
      expect(tokens[token][:created_at]).to eq(fixed_time)
      expect(tokens[token][:last_used]).to eq(fixed_time)
    end

    it 'uses default scope "read" when none is provided' do
      token = manager.generate_token(user_id)
      tokens = manager.instance_variable_get(:@tokens)
      expect(tokens[token][:scope]).to eq('read')
    end

    it 'generates different tokens for different calls' do
      allow(SecureRandom).to receive(:urlsafe_base64).and_return('token-1', 'token-2')
      token1 = manager.generate_token(user_id)
      token2 = manager.generate_token(user_id)
      expect(token1).not_to eq(token2)
      expect(manager.instance_variable_get(:@tokens).keys).to match_array(['token-1', 'token-2'])
    end
  end

  describe '#verify_token' do
    let(:user_id) do
      456
    end

    let(:initial_time) do
      Time.now
    end

    let(:later_time) do
      initial_time + 60
    end

    let(:token) do
      manager.generate_token(user_id)
    end

    before do
      allow(Time).to receive(:now).and_return(initial_time)
      token
    end

    context 'when the token exists' do
      it 'returns the associated user_id' do
        allow(Time).to receive(:now).and_return(later_time)
        result = manager.verify_token(token)
        expect(result).to eq(user_id)
      end

      it 'updates the last_used timestamp' do
        allow(Time).to receive(:now).and_return(later_time)
        manager.verify_token(token)
        tokens = manager.instance_variable_get(:@tokens)
        expect(tokens[token][:last_used]).to eq(later_time)
      end
    end

    context 'when the token does not exist' do
      it 'returns nil' do
        result = manager.verify_token('non-existent-token')
        expect(result).to be_nil
      end

      it 'does not raise an error' do
        expect do
          manager.verify_token('non-existent-token')
        end.not_to raise_error
      end
    end

    context 'when token is nil' do
      it 'returns nil without raising an error' do
        expect do
          result = manager.verify_token(nil)
          expect(result).to be_nil
        end.not_to raise_error
      end
    end
  end

  describe '#revoke_token' do
    let(:user_id) do
      789
    end

    let!(:token) do
      manager.generate_token(user_id)
    end

    it 'removes the token from the store' do
      expect(manager.instance_variable_get(:@tokens)).to have_key(token)
      manager.revoke_token(token)
      expect(manager.instance_variable_get(:@tokens)).not_to have_key(token)
    end

    it 'returns the stored token data when revoking existing token' do
      tokens = manager.instance_variable_get(:@tokens)
      stored_data = tokens[token]
      result = manager.revoke_token(token)
      expect(result).to eq(stored_data)
    end

    it 'returns nil when revoking non-existent token' do
      result = manager.revoke_token('non-existent-token')
      expect(result).to be_nil
    end

    it 'handles nil token gracefully' do
      expect do
        result = manager.revoke_token(nil)
        expect(result).to be_nil
      end.not_to raise_error
    end
  end

  describe '#get_token_scope' do
    let(:user_id) do
      111
    end

    let!(:token) do
      manager.generate_token(user_id, scope: 'admin')
    end

    context 'when the token exists' do
      it 'returns the correct scope' do
        scope = manager.get_token_scope(token)
        expect(scope).to eq('admin')
      end
    end

    context 'when the token does not exist' do
      it 'returns nil' do
        scope = manager.get_token_scope('missing-token')
        expect(scope).to be_nil
      end
    end

    context 'when token is nil' do
      it 'returns nil without raising an error' do
        expect do
          scope = manager.get_token_scope(nil)
          expect(scope).to be_nil
        end.not_to raise_error
      end
    end
  end

  describe '#update_token_scope' do
    let(:user_id) do
      222
    end

    let!(:token) do
      manager.generate_token(user_id, scope: 'read')
    end

    context 'when the token exists' do
      it 'updates the scope and returns true' do
        result = manager.update_token_scope(token, 'write')
        expect(result).to be true
        scope = manager.get_token_scope(token)
        expect(scope).to eq('write')
      end

      it 'allows updating to an empty scope string' do
        result = manager.update_token_scope(token, '')
        expect(result).to be true
        scope = manager.get_token_scope(token)
        expect(scope).to eq('')
      end

      it 'allows updating to nil scope (even though unusual)' do
        result = manager.update_token_scope(token, nil)
        expect(result).to be true
        tokens = manager.instance_variable_get(:@tokens)
        expect(tokens[token][:scope]).to be_nil
      end
    end

    context 'when the token does not exist' do
      it 'returns false and does not raise an error' do
        expect do
          result = manager.update_token_scope('missing-token', 'write')
          expect(result).to be false
        end.not_to raise_error
      end
    end

    context 'when token is nil' do
      it 'returns false without raising an error' do
        expect do
          result = manager.update_token_scope(nil, 'write')
          expect(result).to be false
        end.not_to raise_error
      end
    end
  end

  describe '#all_tokens_for_user' do
    let(:user_id_1) do
      1
    end

    let(:user_id_2) do
      2
    end

    let!(:token1_user1) do
      manager.generate_token(user_id_1, scope: 'read')
    end

    let!(:token2_user1) do
      manager.generate_token(user_id_1, scope: 'write')
    end

    let!(:token1_user2) do
      manager.generate_token(user_id_2, scope: 'read')
    end

    it 'returns all tokens belonging to the specified user' do
      tokens = manager.all_tokens_for_user(user_id_1)
      expect(tokens).to match_array([token1_user1, token2_user1])
    end

    it 'does not include tokens from other users' do
      tokens = manager.all_tokens_for_user(user_id_1)
      expect(tokens).not_to include(token1_user2)
    end

    it 'returns an empty array when user has no tokens' do
      tokens = manager.all_tokens_for_user(999)
      expect(tokens).to eq([])
    end

    it 'returns an empty array for nil user_id when no tokens with nil user_id' do
      tokens = manager.all_tokens_for_user(nil)
      expect(tokens).to eq([])
    end

    it 'includes tokens with nil user_id when present' do
      token_nil_user = manager.generate_token(nil)
      tokens = manager.all_tokens_for_user(nil)
      expect(tokens).to include(token_nil_user)
    end
  end

  describe 'external dependency mocking' do
    describe '#generate_token and SecureRandom' do
      it 'uses SecureRandom.urlsafe_base64 to generate tokens' do
        allow(SecureRandom).to receive(:urlsafe_base64).and_return('mocked-token')
        token = manager.generate_token(10)
        expect(SecureRandom).to have_received(:urlsafe_base64).with(32)
        expect(token).to eq('mocked-token')
      end
    end

    describe 'Time.now usage' do
      it 'uses Time.now for timestamps without raising errors' do
        allow(Time).to receive(:now).and_return(Time.new(2020, 1, 1, 0, 0, 0))
        token = manager.generate_token(10)
        tokens = manager.instance_variable_get(:@tokens)
        expect(tokens[token][:created_at]).to eq(Time.new(2020, 1, 1, 0, 0, 0))
        expect(tokens[token][:last_used]).to eq(Time.new(2020, 1, 1, 0, 0, 0))
      end
    end
  end
end
