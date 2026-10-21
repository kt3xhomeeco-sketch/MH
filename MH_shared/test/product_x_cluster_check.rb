# encoding: UTF-8
require 'json'
require_relative '../product_x_cluster'
fixtures = JSON.parse(File.read(ARGV.fetch(0), encoding: 'UTF-8'), symbolize_names: true)
fixtures.each do |fixture|
  markers = MH::ProductXCluster.group_markers(fixture[:markers], fixture.fetch(:groupGapMm, 0))
  result = MH::ProductXCluster.resolve(fixture[:items], markers)
  expected = fixture[:expected].transform_keys(&:to_s)
  raise fixture[:name] unless result[:owners] == expected && result[:ambiguous].sort == fixture[:ambiguous].sort
end
puts "Ruby world X: #{fixtures.length} fixtures passed."
