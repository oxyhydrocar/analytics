require 'rails_helper'
require_relative '../../app/services/request_cache'
require 'spec_helper'

RSpec.describe RequestCache do
  describe '#initialize' do
    context 'with default options' do
      let(:cache) do
        described_class.new
      end

      it 'initializes with empty cache' do
        expect(cache.size).to eq(0)
      end
    end

    context 'with custom max_entries' do
      let(:max_entries) do
        10
      end

      let(:cache) do
        described_class.new(max_entries: max_entries)
      end

      it 'sets the max_entries instance variable' do
        expect(cache.instance_variable_get(:@max_entries)).to eq(max_entries)
      end
    end
  end

  describe '#set' do
    let(:cache) do
      described_class.new(max_entries: max_entries)
    end

    let(:max_entries) do
      3
    end

    let(:request_data) do
      { a: 1, b: 2 }
    end

    let(:response_data) do
      { result: 'ok' }
    end

    context 'with default ttl' do
      it 'stores the data in the cache' do
        cache.set(request_data, response_data)
        expect(cache.size).to eq(1)
        expect(cache.get(request_data)).to eq(response_data)
      end

      it 'sets expires_at to a future time' do
        now = Time.now
        allow(Time).to receive(:now).and_return(now, now)
        cache.set(request_data, response_data)
        key = cache.send(:cache_key, request_data)
        entry = cache.instance_variable_get(:@cache)[key]
        expect(entry[:expires_at]).to be_within(1).of(now + 300)
      end

      it 'sets created_at to now' do
        now = Time.now
        allow(Time).to receive(:now).and_return(now, now)
        cache.set(request_data, response_data)
        key = cache.send(:cache_key, request_data)
        entry = cache.instance_variable_get(:@cache)[key]
        expect(entry[:created_at]).to eq(now)
      end
    end

    context 'with custom ttl' do
      it 'sets expires_at according to ttl' do
        now = Time.now
        allow(Time).to receive(:now).and_return(now, now)
        cache.set(request_data, response_data, ttl: 10)
        key = cache.send(:cache_key, request_data)
        entry = cache.instance_variable_get(:@cache)[key]
        expect(entry[:expires_at]).to be_within(1).of(now + 10)
      end
    end

    context 'with nil ttl (no expiration)' do
      it 'stores data without expires_at' do
        cache.set(request_data, response_data, ttl: nil)
        key = cache.send(:cache_key, request_data)
        entry = cache.instance_variable_get(:@cache)[key]
        expect(entry[:expires_at]).to be_nil
      end
    end

    context 'when cache is at capacity' do
      let(:first_request) do
        { id: 1 }
      end

      let(:second_request) do
        { id: 2 }
      end

      let(:third_request) do
        { id: 3 }
      end

      let(:fourth_request) do
        { id: 4 }
      end

      it 'evicts the oldest entry before adding a new one' do
        t1 = Time.now
        t2 = t1 + 1
        t3 = t1 + 2
        t4 = t1 + 3

        allow(Time).to receive(:now).and_return(t1, t1, t2, t2, t3, t3, t4, t4)

        cache.set(first_request, 'first')
        cache.set(second_request, 'second')
        cache.set(third_request, 'third')

        expect(cache.size).to eq(3)
        expect(cache.get(first_request)).to eq('first')

        cache.set(fourth_request, 'fourth')

        expect(cache.size).to eq(3)
        expect(cache.get(first_request)).to be_nil
        expect(cache.get(second_request)).to eq('second')
        expect(cache.get(third_request)).to eq('third')
        expect(cache.get(fourth_request)).to eq('fourth')
      end
    end
  end

  describe '#get' do
    let(:cache) do
      described_class.new
    end

    let(:request_data) do
      { a: 1, b: 2 }
    end

    let(:response_data) do
      { result: 'ok' }
    end

    context 'when entry does not exist' do
      it 'returns nil' do
        expect(cache.get(request_data)).to be_nil
      end
    end

    context 'when entry exists and is not expired' do
      before do
        cache.set(request_data, response_data, ttl: 300)
      end

      it 'returns the cached data' do
        expect(cache.get(request_data)).to eq(response_data)
      end
    end

    context 'when entry is expired' do
      it 'returns nil and removes the entry from cache' do
        now = Time.now
        past = now - 10
        future = now + 300

        allow(Time).to receive(:now).and_return(now, now, future)

        cache.set(request_data, response_data, ttl: 1)

        key = cache.send(:cache_key, request_data)
        entry = cache.instance_variable_get(:@cache)[key]
        entry[:expires_at] = past

        result = cache.get(request_data)
        expect(result).to be_nil
        expect(cache.size).to eq(0)
      end
    end

    context 'with hash request data having different key order' do
      let(:request_data_alt) do
        { b: 2, a: 1 }
      end

      before do
        cache.set(request_data, response_data)
      end

      it 'treats them as the same key' do
        expect(cache.get(request_data_alt)).to eq(response_data)
      end
    end

    context 'with non-hash request data' do
      let(:string_request) do
        'simple-key'
      end

      before do
        cache.set(string_request, response_data)
      end

      it 'uses the string representation consistently' do
        expect(cache.get(string_request)).to eq(response_data)
        expect(cache.get(:'simple-key')).to_not eq(response_data)
      end
    end
  end

  describe '#invalidate' do
    let(:cache) do
      described_class.new
    end

    let(:request_data) do
      { a: 1 }
    end

    let(:response_data) do
      'data'
    end

    before do
      cache.set(request_data, response_data)
    end

    it 'removes the entry from the cache' do
      expect(cache.get(request_data)).to eq(response_data)
      cache.invalidate(request_data)
      expect(cache.get(request_data)).to be_nil
      expect(cache.size).to eq(0)
    end

    it 'does nothing if the key does not exist' do
      expect do
        cache.invalidate({ b: 2 })
      end.not_to change(cache, :size)
    end
  end

  describe '#clear' do
    let(:cache) do
      described_class.new
    end

    before do
      cache.set('a', 1)
      cache.set('b', 2)
    end

    it 'clears all entries' do
      expect(cache.size).to eq(2)
      cache.clear
      expect(cache.size).to eq(0)
      expect(cache.get('a')).to be_nil
      expect(cache.get('b')).to be_nil
    end
  end

  describe '#size' do
    let(:cache) do
      described_class.new
    end

    it 'returns the number of entries in the cache' do
      expect(cache.size).to eq(0)
      cache.set('a', 1)
      cache.set('b', 2)
      expect(cache.size).to eq(2)
    end
  end

  describe 'cache key generation' do
    let(:cache) do
      described_class.new
    end

    context 'when Time.now raises an error' do
      let(:request_data) do
        { a: 1 }
      end

      it 'propagates the error on set' do
        allow(Time).to receive(:now).and_raise(StandardError.new('time failure'))
        expect do
          cache.set(request_data, 'data')
        end.to raise_error(StandardError, 'time failure')
      end

      it 'propagates the error on get when computing expiration' do
        allow(Time).to receive(:now).and_return(Time.now)
        cache.set(request_data, 'data', ttl: 10)
        allow(Time).to receive(:now).and_raise(StandardError.new('time failure on get'))
        expect do
          cache.get(request_data)
        end.to raise_error(StandardError, 'time failure on get')
      end
    end

    context 'when hashing data' do
      let(:hash_data_1) do
        { a: 1, b: 2 }
      end

      let(:hash_data_2) do
        { b: 2, a: 1 }
      end

      let(:string_data) do
        'test'
      end

      it 'generates the same key for hashes with different order' do
        key1 = cache.send(:cache_key, hash_data_1)
        key2 = cache.send(:cache_key, hash_data_2)
        expect(key1).to eq(key2)
      end

      it 'generates different keys for different contents' do
        key1 = cache.send(:cache_key, hash_data_1)
        key2 = cache.send(:cache_key, { a: 2, b: 3 })
        expect(key1).not_to eq(key2)
      end

      it 'generates a key based on string representation for non-hash' do
        key1 = cache.send(:cache_key, string_data)
        key2 = cache.send(:cache_key, string_data.to_sym)
        expect(key1).not_to eq(key2)
      end
    end
  end
end
