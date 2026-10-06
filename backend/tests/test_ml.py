from app.ml_features import TripContext, feature_vector, synthetic_weight
from app.ml_scorer import FeedbackStats, _Event


def test_item_is_one_hot_not_a_number():
    spec = {"version": 2, "activities": ["beach", "hiking"], "item_ids": [1, 2, 3]}
    ctx = TripContext(6.8, 81.0, 3, 2, 24.0, 70.0, ["rain", "normal"], "normal", ["Hiking"])
    v2 = feature_vector(spec, ctx, 2)
    v3 = feature_vector(spec, ctx, 3)
    assert v2[-3:] == [0.0, 1.0, 0.0]
    assert v3[-3:] == [0.0, 0.0, 1.0]
    assert v2[-5:-3] == [0.0, 1.0]  # hiking on, beach off
    assert feature_vector(spec, ctx, 99)[-3:] == [0.0, 0.0, 0.0]  # unknown item


def test_synthetic_fades_with_real_data():
    assert synthetic_weight(0, 300) == 1.0
    assert synthetic_weight(150, 300) == 0.5
    assert synthetic_weight(10_000, 300) == 0.05


def test_stats_weight_real_over_synthetic():
    stats = FeedbackStats()
    hike = frozenset({"hiking"})
    rain = frozenset({"rain"})
    stats.by_item[5] = [_Event(0, 0.05, hike, rain) for _ in range(10)] + [_Event(1, 1.0, hike, rain) for _ in range(3)]
    assert stats.overall(5) > 0.8
    assert stats.similar(5, ["hiking"], ["rain"]) > 0.8
    assert stats.similar(5, ["beach"], ["rain"]) is None
    assert stats.overall(6) is None
