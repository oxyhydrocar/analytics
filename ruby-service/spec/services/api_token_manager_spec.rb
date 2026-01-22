require 'rails_helper'
require_relative '../../app/services/api_token_manager'
require 'spec_helper'

RSpec.describe ApiTokenManager do
  describe '#initialize' do
    it 'initializes with an empty token store' do
      manager = described_class.new
      tokens_instance_variable = manager.instance_variable_get(:@tokens)
      expect(tokens_instance_variable).to eq({})
    end
  end

  describe '#generate_token' do
    let(:manager) do
      described_class.new
    end

    let(:user_id) do
      123
    end

    let(:fake_token) do
      'fake_generated_token'
    end

    before do
      allow(SecureRandom).to receive(:urlsafe_base64).with(32).and_return(fake_token)
    end

    it 'returns a token string' do
      token = manager.generate_token(user_id)
      expect(token).to eq(fake_token)
    end

    it 'stores the token with correct user_id and default scope' do
      now = Time.now
      allow(Time).to receive(:now).and_return(now)
      token = manager.generate_token(user_id)
      tokens = manager.instance_variable_get(:@tokens)
      expect(tokens[token][:user_id]).to eq(user_id)
      expect(tokens[token][:scope]).to eq('read')
      expect(tokens[token][:created_at]).to eq(now)
      expect(tokens[token][:last_used]).to eq(now)
    end

    it 'allows specifying a custom scope' do
      token = manager.generate_token(user_id, scope: 'write')
      tokens = manager.instance_variable_get(:@tokens)
      expect(tokens[token][:scope]).to eq('write')
    end

    it 'generates different tokens for multiple calls' do
      allow(SecureRandom).to receive(:urlsafe_base64).with(32).and_return('token1', 'token2')
      token1 = manager.generate_token(user_id)
      token2 = manager.generate_token(user_id)
      expect(token1).not_to eq(token2)
    end
  end

  describe '#verify_token' do
    let(:manager) do
      described_class.new
    end

    let(:user_id) do
      456
    end

    let(:token) do
      'verify_token'
    end

    let!(:generated_token) do
      allow(SecureRandom).to receive(:urlsafe_base64).and_return(token)
      manager.generate_token(user_id)
    end

    context 'when token exists' do
      it 'returns the associated user_id' do
        result = manager.verify_token(token)
        expect(result).to eq(user_id)
      end

      it 'updates the last_used timestamp' do
        initial_last_used = manager.instance_variable_get(:@tokens)[token][:last_used]
        later_time = initial_last_used + 60
        allow(Time).to receive(:now).and_return(later_time)
        manager.verify_token(token)
        updated_last_used = manager.instance_variable_get(:@tokens)[token][:last_used]
        expect(updated_last_used).to eq(later_time)
      end
    end

    context 'when token does not exist' do
      it 'returns nil' do
        result = manager.verify_token('nonexistent')
        expect(result).to be_nil
      end

      it 'does not raise an error' do
        expect do
          manager.verify_token('nonexistent')
        end.not_to raise_error
      end
    end

    context 'when token is nil' do
      it 'returns nil' do
        result = manager.verify_token(nil)
        expect(result).to be_nil
      end
    end

    context 'when token is an empty string' do
      it 'returns nil' do
        result = manager.verify_token('')
        expect(result).to be_nil
      end
    end
  end

  describe '#revoke_token' do
    let(:manager) do
      described_class.new
    end

    let(:user_id) do
      789
    end

    let(:token) do
      'revoke_token'
    end

    let!(:generated_token) do
      allow(SecureRandom).to receive(:urlsafe_base64).and_return(token)
      manager.generate_token(user_id)
    end

    context 'when token exists' do
      it 'removes the token from the store' do
        expect(manager.instance_variable_get(:@tokens)).to have_key(token)
        manager.revoke_token(token)
        expect(manager.instance_variable_get(:@tokens)).not_to have_key(token)
      end

      it 'returns the removed token data' do
        tokens_before = manager.instance_variable_get(:@tokens).dup
        removed = manager.revoke_token(token)
        expect(removed).to eq(tokens_before[token])
      end
    end

    context 'when token does not exist' do
      it 'returns nil' do
        result = manager.revoke_token('nonexistent')
        expect(result).to be_nil
      end

      it 'does not raise an error' do
        expect do
          manager.revoke_token('nonexistent')
        end.not_to raise_error
      end
    end
  end

  describe '#get_token_scope' do
    let(:manager) do
      described_class.new
    end

    let(:user_id) do
      111
    end

    let(:token) do
      'scope_token'
    end

    before do
      allow(SecureRandom).to receive(:urlsafe_base64).and_return(token)
      manager.generate_token(user_id, scope: 'admin')
    end

    context 'when token exists' do
      it 'returns the token scope' do
        scope = manager.get_token_scope(token)
        expect(scope).to eq('admin')
      end
    end

    context 'when token does not exist' do
      it 'returns nil' do
        scope = manager.get_token_scope('nonexistent')
        expect(scope).to be_nil
      end
    end

    context 'when token is nil' do
      it 'returns nil' do
        scope = manager.get_token_scope(nil)
        expect(scope).to be_nil
      end
    end
  end

  describe '#update_token_scope' do
    let(:manager) do
      described_class.new
    end

    let(:user_id) do
      222
    end

    let(:token) do
      'update_scope_token'
    end

    before do
      allow(SecureRandom).to receive(:urlsafe_base64).and_return(token)
      manager.generate_token(user_id, scope: 'read')
    end

    context 'when token exists' do
      it 'updates the scope and returns true' do
        result = manager.update_token_scope(token, 'write')
        expect(result).to eq(true)
        scope = manager.get_token_scope(token)
        expect(scope).to eq('write')
      end

      it 'allows updating scope to nil' do
        result = manager.update_token_scope(token, nil)
        expect(result).to eq(true)
        scope = manager.get_token_scope(token)
        expect(scope).to be_nil
      end
    end

    context 'when token does not exist' do
      it 'returns false' do
        result = manager.update_token_scope('nonexistent', 'write')
        expect(result).to eq(false)
      end

      it 'does not raise an error' do
        expect do
          manager.update_token_scope('nonexistent', 'write')
        end.not_to raise_error
      end
    end
  end

  describe '#all_tokens_for_user' do
    let(:manager) do
      described_class.new
    end

    let(:user_id_1) do
      1
    end

    let(:user_id_2) do
      2
    end

    let!(:token1) do
      allow(SecureRandom).to receive(:urlsafe_base64).and_return('token1')
      manager.generate_token(user_id_1)
    end

    let!(:token2) do
      allow(SecureRandom).to receive(:urlsafe_base64).and_return('token2')
      manager.generate_token(user_id_1)
    end

    let!(:token3) do
      allow(SecureRandom).to receive(:urlsafe_base64).and_return('token3')
      manager.generate_token(user_id_2)
    end

    it 'returns all tokens associated with the given user_id' do
      tokens = manager.all_tokens_for_user(user_id_1)
      expect(tokens).to contain_exactly('token1', 'token2')
    end

    it 'does not include tokens for other users' do
      tokens = manager.all_tokens_for_user(user_id_1)
      expect(tokens).not_to include('token3')
    end

    it 'returns an empty array when the user has no tokens' do
      tokens = manager.all_tokens_for_user(999)
      expect(tokens).to eq([])
    end

    it 'handles nil user_id and returns empty array' do
      tokens = manager.all_tokens_for_user(nil)
      expect(tokens).to eq([])
    end
  end
end
