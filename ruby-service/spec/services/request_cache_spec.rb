require 'rails_helper'
require_relative '../../app/services/request_cache'
require 'spec_helper'

RSpec.describe RequestCache do
  describe '#initialize' do
    context 'with default arguments' do
      let(:cache) do
        described_class.new
      end

      it 'initializes an empty cache' do
        expect(cache.size).to eq(0)
      end
    end

    context 'with custom max_entries' do
      let(:cache) do
        described_class.new(max_entries: 10)
      end

      it 'sets the max_entries value' do
        expect(cache.instance_variable_get(:@max_entries)).to eq(10)
      end
    end
  end

  describe '#set' do
    let(:cache) do
      described_class.new
    end

    let(:request_data) do
      { foo: 'bar' }
    end

    let(:response_data) do
      { result: 'ok' }
    end

    context 'with default ttl' do
      it 'stores the response in the cache' do
        cache.set(request_data, response_data)
        expect(cache.size).to eq(1)
      end

      it 'sets data and metadata correctly' do
        frozen_time = Time.now
        allow(Time).to receive(:now).and_return(frozen_time)

        cache.set(request_data, response_data)
        key = cache.send(:cache_key, request_data)
        entry = cache.instance_variable_get(:@cache)[key]

        expect(entry[:data]).to eq(response_data)
        expect(entry[:created_at]).to eq(frozen_time)
        expect(entry[:expires_at]).to eq(frozen_time + 300)
      end
    end

    context 'with custom ttl' do
      it 'uses the provided ttl value' do
        frozen_time = Time.now
        allow(Time).to receive(:now).and_return(frozen_time)

        cache.set(request_data, response_data, ttl: 120)
        key = cache.send(:cache_key, request_data)
        entry = cache.instance_variable_get(:@cache)[key]

        expect(entry[:expires_at]).to eq(frozen_time + 120)
      end
    end

    context 'with nil ttl (no expiration)' do
      it 'does not set expires_at' do
        frozen_time = Time.now
        allow(Time).to receive(:now).and_return(frozen_time)

        cache.set(request_data, response_data, ttl: nil)
        key = cache.send(:cache_key, request_data)
        entry = cache.instance_variable_get(:@cache)[key]

        expect(entry[:expires_at]).to be_nil
      end
    end

    context 'when max_entries is reached' do
      let(:cache) do
        described_class.new(max_entries: 2)
      end

      it 'evicts the oldest entry' do
        allow(Time).to receive(:now).and_return(Time.now)
        cache.set({ id: 1 }, 'one')
        sleep 0.01
        cache.set({ id: 2 }, 'two')
        sleep 0.01

        expect(cache.size).to eq(2)

        cache.set({ id: 3 }, 'three')

        expect(cache.size).to eq(2)
        expect(cache.get({ id: 1 })).to be_nil
        expect(cache.get({ id: 2 })).to eq('two')
        expect(cache.get({ id: 3 })).to eq('three')
      end
    end
  end

  describe '#get' do
    let(:cache) do
      described_class.new
    end

    let(:request_data) do
      { foo: 'bar' }
    end

    let(:response_data) do
      { result: 'ok' }
    end

    context 'when entry exists and is not expired' do
      it 'returns the cached data' do
        cache.set(request_data, response_data)
        expect(cache.get(request_data)).to eq(response_data)
      end

      it 'is idempotent for repeated calls' do
        cache.set(request_data, response_data)
        3.times do
          expect(cache.get(request_data)).to eq(response_data)
        end
      end
    end

    context 'when entry does not exist' do
      it 'returns nil' do
        expect(cache.get(request_data)).to be_nil
      end
    end

    context 'when entry is expired' do
      it 'returns nil and removes the entry' do
        frozen_time = Time.now
        allow(Time).to receive(:now).and_return(frozen_time)
        cache.set(request_data, response_data, ttl: 1)

        allow(Time).to receive(:now).and_return(frozen_time + 2)

        expect(cache.get(request_data)).to be_nil
        expect(cache.size).to eq(0)
      end
    end

    context 'when ttl is nil (no expiration)' do
      it 'never expires the entry automatically' do
        frozen_time = Time.now
        allow(Time).to receive(:now).and_return(frozen_time)
        cache.set(request_data, response_data, ttl: nil)

        allow(Time).to receive(:now).and_return(frozen_time + 10_000)

        expect(cache.get(request_data)).to eq(response_data)
      end
    end

    context 'with different but equivalent hash key order' do
      let(:request_data_alt) do
        { bar: 'baz', foo: 'bar' }
      end

      it 'treats hashes with same content but different order as same key' do
        cache.set({ foo: 'bar', bar: 'baz' }, response_data)
        expect(cache.get(request_data_alt)).to eq(response_data)
      end
    end

    context 'with non-hash request data' do
      it 'uses string representation for cache key' do
        cache.set('simple-key', response_data)
        expect(cache.get('simple-key')).to eq(response_data)
      end

      it 'distinguishes between different non-hash inputs' do
        cache.set('1', 'string-one')
        cache.set(1, 'integer-one')

        expect(cache.get('1')).to eq('string-one')
        expect(cache.get(1)).to eq('integer-one')
      end
    end
  end

  describe '#invalidate' do
    let(:cache) do
      described_class.new
    end

    let(:request_data) do
      { foo: 'bar' }
    end

    let(:response_data) do
      { result: 'ok' }
    end

    context 'when entry exists' do
      before do
        cache.set(request_data, response_data)
      end

      it 'removes the entry from the cache' do
        expect(cache.get(request_data)).to eq(response_data)
        cache.invalidate(request_data)
        expect(cache.get(request_data)).to be_nil
        expect(cache.size).to eq(0)
      end
    end

    context 'when entry does not exist' do
      it 'does not raise error and keeps cache unchanged' do
        cache.set(request_data, response_data)
        expect do
          cache.invalidate({ other: 'data' })
        end.not_to raise_error
        expect(cache.size).to eq(1)
      end
    end
  end

  describe '#clear' do
    let(:cache) do
      described_class.new
    end

    before do
      cache.set('one', 1)
      cache.set('two', 2)
    end

    it 'removes all entries from the cache' do
      expect(cache.size).to eq(2)
      cache.clear
      expect(cache.size).to eq(0)
      expect(cache.get('one')).to be_nil
      expect(cache.get('two')).to be_nil
    end
  end

  describe '#size' do
    let(:cache) do
      described_class.new
    end

    it 'returns the number of items in the cache' do
      expect(cache.size).to eq(0)
      cache.set('a', 1)
      expect(cache.size).to eq(1)
      cache.set('b', 2)
      expect(cache.size).to eq(2)
      cache.invalidate('a')
      expect(cache.size).to eq(1)
    end
  end

  describe 'error handling and edge cases' do
    let(:cache) do
      described_class.new
    end

    it 'handles nil request_data gracefully' do
      cache.set(nil, 'nil-key')
      expect(cache.get(nil)).to eq('nil-key')
      cache.invalidate(nil)
      expect(cache.get(nil)).to be_nil
    end

    it 'handles complex nested hashes consistently' do
      data1 = { b: { y: 2, x: 1 }, a: 1 }
      data2 = { a: 1, b: { x: 1, y: 2 } }

      cache.set(data1, 'nested')
      expect(cache.get(data2)).to eq('nested')
    end

    it 'does not raise errors when evicting from an empty cache' do
      empty_cache = described_class.new(max_entries: 0)
      expect do
        empty_cache.send(:evict_if_needed)
      end.not_to raise_error
    end
  end

  describe 'private methods' do
    describe '#cache_key' do
      let(:cache) do
        described_class.new
      end

      it 'produces deterministic keys for equivalent hashes' do
        h1 = { a: 1, b: 2 }
        h2 = { b: 2, a: 1 }

        key1 = cache.send(:cache_key, h1)
        key2 = cache.send(:cache_key, h2)

        expect(key1).to eq(key2)
      end

      it 'produces different keys for different content' do
        key1 = cache.send(:cache_key, { a: 1 })
        key2 = cache.send(:cache_key, { a: 2 })
        expect(key1).not_to eq(key2)
      end
    end

    describe '#evict_if_needed' do
      let(:cache) do
        described_class.new(max_entries: 1)
      end

      it 'does nothing when under capacity' do
        cache.set('a', 1)
        expect(cache.size).to eq(1)
        cache.send(:evict_if_needed)
        expect(cache.size).to eq(1)
      end

      it 'evicts oldest when at capacity and new entry added via set' do
        allow(Time).to receive(:now).and_return(Time.now)
        cache.set('a', 1)
        sleep 0.01
        cache.set('b', 2)

        expect(cache.get('a')).to be_nil
        expect(cache.get('b')).to eq(2)
      end
    end
  end
end
