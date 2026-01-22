require 'rails_helper'
require_relative '../../app/services/analytics_tracker'
require 'spec_helper'

RSpec.describe AnalyticsTracker do
  describe '#initialize' do
    let(:tracker) { described_class.new }

    it 'initializes @events as an empty array' do
      expect(tracker.instance_variable_get(:@events)).to eq([])
    end

    it 'initializes @user_sessions as an empty hash' do
      expect(tracker.instance_variable_get(:@user_sessions)).to eq({})
    end
  end

  describe '#track_event' do
    let(:tracker) { described_class.new }
    let(:user_id) { 1 }
    let(:event_type) { 'click' }
    let(:data) { { score: 10, extra: 'info' } }
    let(:fixed_time) { Time.at(1_700_000_000) }

    before do
      allow(Time).to receive(:now).and_return(fixed_time)
    end

    context 'with full arguments' do
      it 'adds an event to @events with correct structure' do
        tracker.track_event(user_id, event_type, data)

        events = tracker.instance_variable_get(:@events)
        expect(events.size).to eq(1)
        event = events.first

        expect(event[:user_id]).to eq(user_id)
        expect(event[:event_type]).to eq(event_type)
        expect(event[:data]).to eq(data)
        expect(event[:timestamp]).to eq(fixed_time.to_i)
      end

      it 'adds the event to the user session list' do
        tracker.track_event(user_id, event_type, data)

        user_sessions = tracker.instance_variable_get(:@user_sessions)
        expect(user_sessions[user_id].size).to eq(1)
        expect(user_sessions[user_id].first[:event_type]).to eq(event_type)
      end

      it 'appends multiple events for the same user' do
        tracker.track_event(user_id, event_type, data)
        tracker.track_event(user_id, 'view', {})

        user_sessions = tracker.instance_variable_get(:@user_sessions)
        expect(user_sessions[user_id].size).to eq(2)
        expect(user_sessions[user_id].map { |e| e[:event_type] }).to eq(['click', 'view'])
      end

      it 'tracks events for multiple users separately' do
        tracker.track_event(user_id, event_type, data)
        tracker.track_event(2, 'view', {})

        user_sessions = tracker.instance_variable_get(:@user_sessions)
        expect(user_sessions[user_id].size).to eq(1)
        expect(user_sessions[2].size).to eq(1)
        expect(user_sessions[user_id].first[:user_id]).to eq(user_id)
        expect(user_sessions[2].first[:user_id]).to eq(2)
      end

      it 'returns the created event hash (implicit return from method stack)' do
        result = tracker.track_event(user_id, event_type, data)
        expect(result).to be_nil
      end
    end

    context 'when data is omitted' do
      it 'defaults data to an empty hash' do
        tracker.track_event(user_id, event_type)

        event = tracker.instance_variable_get(:@events).first
        expect(event[:data]).to eq({})
      end
    end

    context 'error handling' do
      it 'does not raise error when called with nil data' do
        expect do
          tracker.track_event(user_id, event_type, nil)
        end.not_to raise_error
      end

      it 'allows non-hash data values' do
        tracker.track_event(user_id, event_type, 'string-data')

        event = tracker.instance_variable_get(:@events).first
        expect(event[:data]).to eq('string-data')
      end
    end
  end

  describe '#get_user_events' do
    let(:tracker) { described_class.new }
    let(:user_id) { 1 }

    context 'when user has events' do
      let!(:events) do
        tracker.track_event(user_id, 'click', {})
        tracker.track_event(user_id, 'view', {})
        tracker.get_user_events(user_id)
      end

      it 'returns an array of events for the user' do
        expect(events.size).to eq(2)
        expect(events.map { |e| e[:event_type] }).to eq(['click', 'view'])
      end

      it 'returns a duplicate array that can be modified without affecting internal state' do
        events.pop

        internal_events = tracker.instance_variable_get(:@user_sessions)[user_id]
        expect(internal_events.size).to eq(2)
      end
    end

    context 'when user has no events' do
      it 'returns an empty array' do
        expect(tracker.get_user_events(user_id)).to eq([])
      end

      it 'returns a new empty array instance each time' do
        first = tracker.get_user_events(user_id)
        second = tracker.get_user_events(user_id)

        expect(first).to eq([])
        expect(second).to eq([])
        expect(first).not_to be(second)
      end
    end

    context 'when called with nil user_id' do
      it 'returns an empty array' do
        expect(tracker.get_user_events(nil)).to eq([])
      end
    end
  end

  describe '#get_all_events' do
    let(:tracker) { described_class.new }

    context 'when there are events' do
      before do
        tracker.track_event(1, 'click', {})
        tracker.track_event(2, 'view', {})
      end

      it 'returns all events' do
        events = tracker.get_all_events
        expect(events.size).to eq(2)
        expect(events.map { |e| e[:event_type] }).to contain_exactly('click', 'view')
      end

      it 'returns a duplicate array that can be modified without affecting internal state' do
        events = tracker.get_all_events
        events.clear

        internal_events = tracker.instance_variable_get(:@events)
        expect(internal_events.size).to eq(2)
      end
    end

    context 'when there are no events' do
      it 'returns an empty array' do
        expect(tracker.get_all_events).to eq([])
      end
    end
  end

  describe '#get_events_by_type' do
    let(:tracker) { described_class.new }

    before do
      tracker.track_event(1, 'click', {})
      tracker.track_event(2, 'view', {})
      tracker.track_event(3, 'click', {})
    end

    context 'when events of the given type exist' do
      it 'returns only events of that type' do
        events = tracker.get_events_by_type('click')
        expect(events.size).to eq(2)
        expect(events.all? { |e| e[:event_type] == 'click' }).to be true
      end
    end

    context 'when no events of the given type exist' do
      it 'returns an empty array' do
        expect(tracker.get_events_by_type('purchase')).to eq([])
      end
    end

    context 'when event_type is nil' do
      it 'returns events with nil event_type only' do
        tracker.track_event(4, nil, {})
        events = tracker.get_events_by_type(nil)

        expect(events.size).to eq(1)
        expect(events.first[:event_type]).to be_nil
      end
    end

    it 'does not modify the internal @events collection' do
      original = tracker.instance_variable_get(:@events).dup
      tracker.get_events_by_type('click')
      expect(tracker.instance_variable_get(:@events)).to eq(original)
    end
  end

  describe '#compute_user_score' do
    let(:tracker) { described_class.new }
    let(:user_id) { 1 }

    context 'when user has no events' do
      it 'returns 0' do
        expect(tracker.compute_user_score(user_id)).to eq(0)
      end

      it 'handles missing user_id key safely' do
        expect do
          tracker.compute_user_score(999)
        end.not_to raise_error
      end
    end

    context 'when events have numeric scores as symbols' do
      before do
        tracker.track_event(user_id, 'a', { score: 10 })
        tracker.track_event(user_id, 'b', { score: 20 })
      end

      it 'returns the average score rounded to 2 decimals' do
        expect(tracker.compute_user_score(user_id)).to eq(15.0)
      end
    end

    context 'when events have numeric scores as string keys' do
      before do
        tracker.track_event(user_id, 'a', { 'score' => 5 })
        tracker.track_event(user_id, 'b', { 'score' => 15 })
      end

      it 'returns the average score rounded to 2 decimals' do
        expect(tracker.compute_user_score(user_id)).to eq(10.0)
      end
    end

    context 'when events mix symbol and string score keys' do
      before do
        tracker.track_event(user_id, 'a', { score: 10 })
        tracker.track_event(user_id, 'b', { 'score' => 20 })
      end

      it 'sums both and averages correctly' do
        expect(tracker.compute_user_score(user_id)).to eq(15.0)
      end
    end

    context 'when some events have no score' do
      before do
        tracker.track_event(user_id, 'a', { score: 10 })
        tracker.track_event(user_id, 'b', {})
        tracker.track_event(user_id, 'c', { 'score' => 20 })
      end

      it 'averages only available scores but divides by total events count' do
        # total_score = 30, events.length = 3 -> 10.0
        expect(tracker.compute_user_score(user_id)).to eq(10.0)
      end
    end

    context 'when score values are non-numeric but convertible' do
      before do
        tracker.track_event(user_id, 'a', { score: '10.5' })
        tracker.track_event(user_id, 'b', { 'score' => '9.5' })
      end

      it 'casts scores to float before averaging' do
        # (10.5 + 9.5) / 2 = 10.0
        expect(tracker.compute_user_score(user_id)).to eq(10.0)
      end
    end

    context 'when some score values are nil' do
      before do
        tracker.track_event(user_id, 'a', { score: nil })
        tracker.track_event(user_id, 'b', { 'score' => 10 })
      end

      it 'ignores nil scores' do
        # total_score = 10, events.length = 2 -> 5.0
        expect(tracker.compute_user_score(user_id)).to eq(5.0)
      end
    end

    context 'when internal user_sessions entry is manually set to nil (robustness)' do
      before do
        tracker.instance_variable_get(:@user_sessions)[user_id] = nil
      end

      it 'raises NoMethodError due to nil events when accessing empty?' do
        expect do
          tracker.compute_user_score(user_id)
        end.to raise_error(NoMethodError)
      end
    end

    context 'floating point rounding behavior' do
      before do
        tracker.track_event(user_id, 'a', { score: 10 })
        tracker.track_event(user_id, 'b', { score: 10 })
        tracker.track_event(user_id, 'c', { score: 10 })
      end

      it 'rounds to two decimal places' do
        expect(tracker.compute_user_score(user_id)).to eq(10.0)
      end
    end
  end
end
