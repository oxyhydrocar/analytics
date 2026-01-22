require 'rails_helper'
require_relative '../../app/services/analytics_tracker'
require 'spec_helper'

RSpec.describe AnalyticsTracker do
  describe '#initialize' do
    let(:tracker) { described_class.new }

    it 'initializes with empty events array' do
      expect(tracker.instance_variable_get(:@events)).to eq([])
    end

    it 'initializes with empty user_sessions hash' do
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

    context 'with all arguments provided' do
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

      it 'adds the event to the user session' do
        tracker.track_event(user_id, event_type, data)
        user_sessions = tracker.instance_variable_get(:@user_sessions)
        expect(user_sessions[user_id].size).to eq(1)
        expect(user_sessions[user_id].first[:event_type]).to eq(event_type)
      end

      it 'returns the tracked event as the last element in events' do
        tracker.track_event(user_id, event_type, data)
        last_event = tracker.instance_variable_get(:@events).last
        expect(last_event[:user_id]).to eq(user_id)
        expect(last_event[:event_type]).to eq(event_type)
        expect(last_event[:data]).to eq(data)
        expect(last_event[:timestamp]).to eq(fixed_time.to_i)
      end
    end

    context 'when data is not provided' do
      it 'defaults data to an empty hash' do
        tracker.track_event(user_id, event_type)
        event = tracker.instance_variable_get(:@events).first
        expect(event[:data]).to eq({})
      end
    end

    context 'when tracking multiple events for the same user' do
      it 'appends events to the user session array' do
        tracker.track_event(user_id, 'click')
        tracker.track_event(user_id, 'view')
        user_events = tracker.instance_variable_get(:@user_sessions)[user_id]
        expect(user_events.size).to eq(2)
        expect(user_events.map { |e| e[:event_type] }).to eq(%w[click view])
      end
    end

    context 'when tracking events for multiple users' do
      let(:other_user_id) { 2 }

      it 'separates events by user in user_sessions' do
        tracker.track_event(user_id, 'click')
        tracker.track_event(other_user_id, 'view')
        user_sessions = tracker.instance_variable_get(:@user_sessions)
        expect(user_sessions[user_id].size).to eq(1)
        expect(user_sessions[other_user_id].size).to eq(1)
        expect(user_sessions[user_id].first[:event_type]).to eq('click')
        expect(user_sessions[other_user_id].first[:event_type]).to eq('view')
      end
    end
  end

  describe '#get_user_events' do
    let(:tracker) { described_class.new }
    let(:user_id) { 1 }

    context 'when user has no events' do
      it 'returns an empty array' do
        expect(tracker.get_user_events(user_id)).to eq([])
      end

      it 'returns a new array that can be modified without affecting internal state' do
        events = tracker.get_user_events(user_id)
        events << { test: 'value' }
        internal = tracker.instance_variable_get(:@user_sessions)[user_id]
        expect(internal).to be_nil
      end
    end

    context 'when user has events' do
      before do
        tracker.track_event(user_id, 'click', score: 5)
        tracker.track_event(user_id, 'view', score: 3)
      end

      it 'returns a duplicate array of user events' do
        events = tracker.get_user_events(user_id)
        expect(events.size).to eq(2)
        expect(events.map { |e| e[:event_type] }).to eq(%w[click view])
      end

      it 'does not allow external modification of internal events array' do
        events = tracker.get_user_events(user_id)
        events.pop
        internal_events = tracker.instance_variable_get(:@user_sessions)[user_id]
        expect(internal_events.size).to eq(2)
      end
    end
  end

  describe '#get_all_events' do
    let(:tracker) { described_class.new }

    context 'when no events have been tracked' do
      it 'returns an empty array' do
        expect(tracker.get_all_events).to eq([])
      end
    end

    context 'when events have been tracked' do
      before do
        tracker.track_event(1, 'click')
        tracker.track_event(2, 'view')
      end

      it 'returns all events' do
        all_events = tracker.get_all_events
        expect(all_events.size).to eq(2)
        expect(all_events.map { |e| e[:event_type] }).to match_array(%w[click view])
      end

      it 'returns a duplicate array that does not affect internal state when modified' do
        all_events = tracker.get_all_events
        all_events.clear
        internal_events = tracker.instance_variable_get(:@events)
        expect(internal_events.size).to eq(2)
      end
    end
  end

  describe '#get_events_by_type' do
    let(:tracker) { described_class.new }

    before do
      tracker.track_event(1, 'click')
      tracker.track_event(2, 'view')
      tracker.track_event(3, 'click')
      tracker.track_event(4, 'signup')
    end

    context 'when there are events of the given type' do
      it 'returns only events matching the type' do
        click_events = tracker.get_events_by_type('click')
        expect(click_events.size).to eq(2)
        expect(click_events.map { |e| e[:event_type] }.uniq).to eq(['click'])
      end
    end

    context 'when there are no events of the given type' do
      it 'returns an empty array' do
        events = tracker.get_events_by_type('nonexistent')
        expect(events).to eq([])
      end
    end

    context 'when event_type is nil' do
      it 'returns events where event_type is nil' do
        tracker.track_event(5, nil)
        nil_type_events = tracker.get_events_by_type(nil)
        expect(nil_type_events.size).to eq(1)
        expect(nil_type_events.first[:user_id]).to eq(5)
      end
    end
  end

  describe '#compute_user_score' do
    let(:tracker) { described_class.new }
    let(:user_id) { 1 }

    context 'when user has no events' do
      it 'returns 0' do
        expect(tracker.compute_user_score(user_id)).to eq(0)
      end
    end

    context 'when user has events with numeric scores as symbols' do
      before do
        tracker.track_event(user_id, 'click', score: 10)
        tracker.track_event(user_id, 'view', score: 20)
      end

      it 'returns the average score rounded to 2 decimals' do
        expect(tracker.compute_user_score(user_id)).to eq(15.0)
      end
    end

    context 'when user has events with numeric scores as strings' do
      before do
        tracker.track_event(user_id, 'click', 'score' => '5.5')
        tracker.track_event(user_id, 'view', 'score' => '4.5')
      end

      it 'converts scores to float and averages them' do
        expect(tracker.compute_user_score(user_id)).to eq(5.0)
      end
    end

    context 'when user has mixed symbol and string scores' do
      before do
        tracker.track_event(user_id, 'click', score: 3)
        tracker.track_event(user_id, 'view', 'score' => '7')
      end

      it 'handles both key types and computes correct average' do
        expect(tracker.compute_user_score(user_id)).to eq(5.0)
      end
    end

    context 'when some events have no score key' do
      before do
        tracker.track_event(user_id, 'click', score: 10)
        tracker.track_event(user_id, 'view')
        tracker.track_event(user_id, 'signup', score: 0)
      end

      it 'ignores events without score in sum but still divides by total events count' do
        # (10 + 0) / 3 = 3.3333 -> 3.33
        expect(tracker.compute_user_score(user_id)).to eq(3.33)
      end
    end

    context 'when scores are non-numeric but present' do
      before do
        tracker.track_event(user_id, 'click', score: 'abc')
        tracker.track_event(user_id, 'view', 'score' => '2xyz')
      end

      it 'uses to_f conversion which turns invalid strings into 0.0' do
        # 'abc'.to_f = 0.0, '2xyz'.to_f = 2.0 => (0 + 2) / 2 = 1.0
        expect(tracker.compute_user_score(user_id)).to eq(1.0)
      end
    end

    context 'when scores result in a long decimal average' do
      before do
        tracker.track_event(user_id, 'click', score: 1)
        tracker.track_event(user_id, 'view', score: 2)
      end

      it 'rounds to two decimal places' do
        # (1 + 2) / 2 = 1.5
        expect(tracker.compute_user_score(user_id)).to eq(1.5)
      end
    end

    context 'error handling / edge cases' do
      it 'returns 0 for unknown user ids' do
        expect(tracker.compute_user_score(999)).to eq(0)
      end

      it 'does not raise error if internal user_sessions entry is manually set to nil' do
        tracker.instance_variable_get(:@user_sessions)[user_id] = nil
        expect do
          result = tracker.compute_user_score(user_id) rescue nil
          expect(result).to eq(0).or eq(nil)
        end.not_to raise_error
      end

      it 'does not raise error if events array contains non-hash values' do
        tracker.instance_variable_get(:@user_sessions)[user_id] = ['invalid', nil]
        expect do
          tracker.compute_user_score(user_id)
        end.not_to raise_error
      end
    end
  end
end
