require "spec_helper"
require "impl/evaluator_spec_base"

module LaunchDarkly
  module Impl
    describe "Evaluator (general)", :evaluator_spec_base => true do
      subject { Evaluator }

      describe "evaluate" do
        it "returns off variation if flag is off" do
          flag = {
            key: 'feature',
            on: false,
            offVariation: 1,
            fallthrough: { variation: 0 },
            variations: ['a', 'b', 'c']
          }
          user = { key: 'x' }
          detail = EvaluationDetail.new('b', 1, EvaluationReason::off)
          result = basic_evaluator.evaluate(flag, user, factory)
          expect(result.detail).to eq(detail)
          expect(result.events).to eq(nil)
        end

        it "returns nil if flag is off and off variation is unspecified" do
          flag = {
            key: 'feature',
            on: false,
            fallthrough: { variation: 0 },
            variations: ['a', 'b', 'c']
          }
          user = { key: 'x' }
          detail = EvaluationDetail.new(nil, nil, EvaluationReason::off)
          result = basic_evaluator.evaluate(flag, user, factory)
          expect(result.detail).to eq(detail)
          expect(result.events).to eq(nil)
        end

        it "returns an error if off variation is too high" do
          flag = {
            key: 'feature',
            on: false,
            offVariation: 999,
            fallthrough: { variation: 0 },
            variations: ['a', 'b', 'c']
          }
          user = { key: 'x' }
          detail = EvaluationDetail.new(nil, nil,
            EvaluationReason::error(EvaluationReason::ERROR_MALFORMED_FLAG))
          result = basic_evaluator.evaluate(flag, user, factory)
          expect(result.detail).to eq(detail)
          expect(result.events).to eq(nil)
        end

        it "returns an error if off variation is negative" do
          flag = {
            key: 'feature',
            on: false,
            offVariation: -1,
            fallthrough: { variation: 0 },
            variations: ['a', 'b', 'c']
          }
          user = { key: 'x' }
          detail = EvaluationDetail.new(nil, nil,
            EvaluationReason::error(EvaluationReason::ERROR_MALFORMED_FLAG))
          result = basic_evaluator.evaluate(flag, user, factory)
          expect(result.detail).to eq(detail)
          expect(result.events).to eq(nil)
        end

        it "returns off variation if prerequisite is not found" do
          flag = {
            key: 'feature0',
            on: true,
            prerequisites: [{key: 'badfeature', variation: 1}],
            fallthrough: { variation: 0 },
            offVariation: 1,
            variations: ['a', 'b', 'c']
          }
          user = { key: 'x' }
          detail = EvaluationDetail.new('b', 1, EvaluationReason::prerequisite_failed('badfeature'))
          e = EvaluatorBuilder.new(logger).with_unknown_flag('badfeature').build
          result = e.evaluate(flag, user, factory)
          expect(result.detail).to eq(detail)
          expect(result.events).to eq(nil)
        end

        it "reuses prerequisite-failed reason instances if possible" do
          flag = {
            key: 'feature0',
            on: true,
            prerequisites: [{key: 'badfeature', variation: 1}],
            fallthrough: { variation: 0 },
            offVariation: 1,
            variations: ['a', 'b', 'c']
          }
          Model.postprocess_item_after_deserializing!(FEATURES, flag)  # now there's a cached reason
          user = { key: 'x' }
          e = EvaluatorBuilder.new(logger).with_unknown_flag('badfeature').build
          result1 = e.evaluate(flag, user, factory)
          expect(result1.detail.reason).to eq EvaluationReason::prerequisite_failed('badfeature')
          result2 = e.evaluate(flag, user, factory)
          expect(result2.detail.reason).to be result1.detail.reason
        end

        it "returns off variation and event if prerequisite of a prerequisite is not found" do
          flag = {
            key: 'feature0',
            on: true,
            prerequisites: [{key: 'feature1', variation: 1}],
            fallthrough: { variation: 0 },
            offVariation: 1,
            variations: ['a', 'b', 'c'],
            version: 1
          }
          flag1 = {
            key: 'feature1',
            on: true,
            prerequisites: [{key: 'feature2', variation: 1}], # feature2 doesn't exist
            fallthrough: { variation: 0 },
            variations: ['d', 'e'],
            version: 2
          }
          user = { key: 'x' }
          detail = EvaluationDetail.new('b', 1, EvaluationReason::prerequisite_failed('feature1'))
          events_should_be = [{
            kind: 'feature', key: 'feature1', user: user, value: nil, default: nil, variation: nil, version: 2, prereqOf: 'feature0'
          }]
          e = EvaluatorBuilder.new(logger).with_flag(flag1).with_unknown_flag('feature2').build
          result = e.evaluate(flag, user, factory)
          expect(result.detail).to eq(detail)
          expect(result.events).to eq(events_should_be)
        end

        it "returns off variation and event if prerequisite is off" do
          flag = {
            key: 'feature0',
            on: true,
            prerequisites: [{key: 'feature1', variation: 1}],
            fallthrough: { variation: 0 },
            offVariation: 1,
            variations: ['a', 'b', 'c'],
            version: 1
          }
          flag1 = {
            key: 'feature1',
            on: false,
            # note that even though it returns the desired variation, it is still off and therefore not a match
            offVariation: 1,
            fallthrough: { variation: 0 },
            variations: ['d', 'e'],
            version: 2
          }
          user = { key: 'x' }
          detail = EvaluationDetail.new('b', 1, EvaluationReason::prerequisite_failed('feature1'))
          events_should_be = [{
            kind: 'feature', key: 'feature1', user: user, variation: 1, value: 'e', default: nil, version: 2, prereqOf: 'feature0'
          }]
          e = EvaluatorBuilder.new(logger).with_flag(flag1).build
          result = e.evaluate(flag, user, factory)
          expect(result.detail).to eq(detail)
          expect(result.events).to eq(events_should_be)
        end

        it "returns off variation and event if prerequisite is not met" do
          flag = {
            key: 'feature0',
            on: true,
            prerequisites: [{key: 'feature1', variation: 1}],
            fallthrough: { variation: 0 },
            offVariation: 1,
            variations: ['a', 'b', 'c'],
            version: 1
          }
          flag1 = {
            key: 'feature1',
            on: true,
            fallthrough: { variation: 0 },
            variations: ['d', 'e'],
            version: 2
          }
          user = { key: 'x' }
          detail = EvaluationDetail.new('b', 1, EvaluationReason::prerequisite_failed('feature1'))
          events_should_be = [{
            kind: 'feature', key: 'feature1', user: user, variation: 0, value: 'd', default: nil, version: 2, prereqOf: 'feature0'
          }]
          e = EvaluatorBuilder.new(logger).with_flag(flag1).build
          result = e.evaluate(flag, user, factory)
          expect(result.detail).to eq(detail)
          expect(result.events).to eq(events_should_be)
        end

        it "returns fallthrough variation and event if prerequisite is met and there are no rules" do
          flag = {
            key: 'feature0',
            on: true,
            prerequisites: [{key: 'feature1', variation: 1}],
            fallthrough: { variation: 0 },
            offVariation: 1,
            variations: ['a', 'b', 'c'],
            version: 1
          }
          flag1 = {
            key: 'feature1',
            on: true,
            fallthrough: { variation: 1 },
            variations: ['d', 'e'],
            version: 2
          }
          user = { key: 'x' }
          detail = EvaluationDetail.new('a', 0, EvaluationReason::fallthrough)
          events_should_be = [{
            kind: 'feature', key: 'feature1', user: user, variation: 1, value: 'e', default: nil, version: 2, prereqOf: 'feature0'
          }]
          e = EvaluatorBuilder.new(logger).with_flag(flag1).build
          result = e.evaluate(flag, user, factory)
          expect(result.detail).to eq(detail)
          expect(result.events).to eq(events_should_be)
        end

        it "returns an error if fallthrough variation is too high" do
          flag = {
            key: 'feature',
            on: true,
            fallthrough: { variation: 999 },
            offVariation: 1,
            variations: ['a', 'b', 'c']
          }
          user = { key: 'userkey' }
          detail = EvaluationDetail.new(nil, nil, EvaluationReason::error(EvaluationReason::ERROR_MALFORMED_FLAG))
          result = basic_evaluator.evaluate(flag, user, factory)
          expect(result.detail).to eq(detail)
          expect(result.events).to eq(nil)
        end

        it "returns an error if fallthrough variation is negative" do
          flag = {
            key: 'feature',
            on: true,
            fallthrough: { variation: -1 },
            offVariation: 1,
            variations: ['a', 'b', 'c']
          }
          user = { key: 'userkey' }
          detail = EvaluationDetail.new(nil, nil, EvaluationReason::error(EvaluationReason::ERROR_MALFORMED_FLAG))
          result = basic_evaluator.evaluate(flag, user, factory)
          expect(result.detail).to eq(detail)
          expect(result.events).to eq(nil)
        end

        it "returns an error if fallthrough has no variation or rollout" do
          flag = {
            key: 'feature',
            on: true,
            fallthrough: { },
            offVariation: 1,
            variations: ['a', 'b', 'c']
          }
          user = { key: 'userkey' }
          detail = EvaluationDetail.new(nil, nil, EvaluationReason::error(EvaluationReason::ERROR_MALFORMED_FLAG))
          result = basic_evaluator.evaluate(flag, user, factory)
          expect(result.detail).to eq(detail)
          expect(result.events).to eq(nil)
        end

        it "returns an error if fallthrough has a rollout with no variations" do
          flag = {
            key: 'feature',
            on: true,
            fallthrough: { rollout: { variations: [] } },
            offVariation: 1,
            variations: ['a', 'b', 'c']
          }
          user = { key: 'userkey' }
          detail = EvaluationDetail.new(nil, nil, EvaluationReason::error(EvaluationReason::ERROR_MALFORMED_FLAG))
          result = basic_evaluator.evaluate(flag, user, factory)
          expect(result.detail).to eq(detail)
          expect(result.events).to eq(nil)
        end

        it "matches user from targets" do
          flag = {
            key: 'feature',
            on: true,
            targets: [
              { values: [ 'whoever', 'userkey' ], variation: 2 }
            ],
            fallthrough: { variation: 0 },
            offVariation: 1,
            variations: ['a', 'b', 'c']
          }
          user = { key: 'userkey' }
          detail = EvaluationDetail.new('c', 2, EvaluationReason::target_match)
          result = basic_evaluator.evaluate(flag, user, factory)
          expect(result.detail).to eq(detail)
          expect(result.events).to eq(nil)
        end

        describe "experiment rollout behavior" do
          it "sets the in_experiment value if rollout kind is experiment and untracked false" do
            flag = {
              key: 'feature',
              on: true,
              fallthrough: { rollout: { kind: 'experiment', variations: [ { weight: 100000, variation: 1, untracked: false } ]  } },
              offVariation: 1,
              variations: ['a', 'b', 'c']
            }
            user = { key: 'userkey' }
            result = basic_evaluator.evaluate(flag, user, factory)
            expect(result.detail.reason.to_json).to include('"inExperiment":true')
            expect(result.detail.reason.in_experiment).to eq(true)
          end

          it "does not set the in_experiment value if rollout kind is not experiment" do
            flag = {
              key: 'feature',
              on: true,
              fallthrough: { rollout: { kind: 'rollout', variations: [ { weight: 100000, variation: 1, untracked: false } ]  } },
              offVariation: 1,
              variations: ['a', 'b', 'c']
            }
            user = { key: 'userkey' }
            result = basic_evaluator.evaluate(flag, user, factory)
            expect(result.detail.reason.to_json).to_not include('"inExperiment":true')
            expect(result.detail.reason.in_experiment).to eq(nil)
          end

          it "does not set the in_experiment value if rollout kind is experiment and untracked is true" do
            flag = {
              key: 'feature',
              on: true,
              fallthrough: { rollout: { kind: 'experiment', variations: [ { weight: 100000, variation: 1, untracked: true } ]  } },
              offVariation: 1,
              variations: ['a', 'b', 'c']
            }
            user = { key: 'userkey' }
            result = basic_evaluator.evaluate(flag, user, factory)
            expect(result.detail.reason.to_json).to_not include('"inExperiment":true')
            expect(result.detail.reason.in_experiment).to eq(nil)
          end
        end
      end
    end
  end
end
