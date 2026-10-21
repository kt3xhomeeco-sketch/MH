# encoding: UTF-8
require_relative '../reader'

module StudioFixtures
  extend self
  def cabinet(thickness, width: 800.0, height: 720.0, depth: 600.0)
    data = [
      ['left', 'Hông trái', [[0, 0, 0], [thickness, depth, height]]],
      ['right', 'Hông phải', [[width - thickness, 0, 0], [width, depth, height]]],
      ['top', 'Nóc', [[thickness, 0, height - 18], [width - thickness, depth - 8, height]]],
      ['bottom', 'Đáy', [[thickness, 0, 0], [width - thickness, depth - 8, 18]]],
      ['shelf', 'Đợt', [[thickness, 0, height / 2 - 9], [width - thickness, depth - 8, height / 2 + 9]]],
      ['back', 'Hậu', [[thickness, depth - 8, 18], [width - thickness, depth, height - 18]]]
    ]
    parts = data.map do |key, name, bounds|
      bounds = bounds.map { |point| point.map(&:to_f) }
      { 'key' => key, 'name' => name, 'bounds' => bounds,
        'thickness_axis' => MH::ModuleStudio::Core.thickness_axis(bounds),
        'box_verified' => true, 'visible' => true, 'face_count' => 6, 'edge_count' => 12, 'dc_attributes' => {} }
    end
    MH::ModuleStudio::Reader.make_snapshot(parts, "Mẫu kiểm thử #{thickness} mm", thickness, { 'kind' => 'synthetic_test' })
  end

  def samples
    [18.0, 25.0, 21.0].map { |value| cabinet(value) }
  end

  def rule
    MH::ModuleStudio::Core.learn(samples, 'Độ dày hông')
  end
end
