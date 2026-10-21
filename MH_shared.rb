# encoding: UTF-8
#
# MH_shared.rb  -- Loader cho hạ tầng dùng chung của hệ sinh thái plugin MH_*
# ---------------------------------------------------------------------------
# Đây KHÔNG phải là một extension độc lập (không có menu/toolbar). Nó chỉ:
#   1. Nạp các thư viện vendored (rubyzip, sketchup-bridge)
#   2. Cung cấp các module dùng chung:
#        MH::Shared::VendorLoader
#        MH::XlsxIO        -- đọc/ghi .xlsx pure-Ruby
#        MH::ExcelBridge   -- wrapper cấp cao trên XlsxIO
#        MH::Text          -- chuẩn hoá chuỗi / tiếng Việt
#        MH::Bounds        -- bounds/dimensions cache dùng chung
#        MH::SimilarityIndex -- feature cache/index cho loc doi tuong tuong tu
#        MH::TraverseModel -- walker đệ quy dùng chung
#        MH::ModelHub      -- hub observer/cache/signature dùng chung
#        MH::ModelReader   -- đọc raw entity/attribute/bounds/selection dùng chung
#        MH::OverlayEngine -- primitives vẽ viewport overlay/tool 2D dùng chung
#        MH::ProjectData   -- cache RAM cho JSON/payload dự án đã parse
#        MH::Registry      -- API đọc/ghi registry JSON (global + per-project)
#        MH::Settings      -- facade config JSON global/project + backup XLSX
#
# Các plugin khác (MH_Rename, MH_fast_rename, MH_Thongke, MH_material_assign,
# MH_Registry) chỉ cần:  require 'MH_shared'
# ---------------------------------------------------------------------------

module MH
  module Shared
    VERSION = '1.2.0'.freeze
    DIR = File.join(__dir__, 'MH_shared').freeze
    DEBUG = false unless const_defined?(:DEBUG, false)

    module_function

    def dbg(message)
      puts message if DEBUG
    end
  end
end

require File.join(MH::Shared::DIR, 'vendor_loader')
MH::Shared::VendorLoader.load_all

require File.join(MH::Shared::DIR, 'xlsx_io')
require File.join(MH::Shared::DIR, 'excel_bridge')
require File.join(MH::Shared::DIR, 'text')
require File.join(MH::Shared::DIR, 'bounds')
require File.join(MH::Shared::DIR, 'similarity_index')
require File.join(MH::Shared::DIR, 'memo')
require File.join(MH::Shared::DIR, 'traverse_model')
require File.join(MH::Shared::DIR, 'model_hub')
require File.join(MH::Shared::DIR, 'model_reader')
require File.join(MH::Shared::DIR, 'overlay_engine')
require File.join(MH::Shared::DIR, 'measure')
require File.join(MH::Shared::DIR, 'name_grammar')
require File.join(MH::Shared::DIR, 'product_context')
require File.join(MH::Shared::DIR, 'project_data')
require File.join(MH::Shared::DIR, 'registry_api')
require File.join(MH::Shared::DIR, 'material_code')
require File.join(MH::Shared::DIR, 'settings')

geo_dir = File.join(MH::Shared::DIR, 'geometry')
if Dir.exist?(geo_dir)
  require File.join(geo_dir, 'const')

  ordered_geometry = %w[
    util
    edge
    face
    offset_helpers
    offset
    solid
    box
    cluster
    fit
    axes
    board_analyzer
    board_builder
    poly2d
  ]

  loaded_geometry = {}
  ordered_geometry.each do |name|
    file = File.join(geo_dir, "#{name}.rb")
    next unless File.exist?(file)

    require file
    loaded_geometry[File.expand_path(file)] = true
  end

  Dir.glob(File.join(geo_dir, '*.rb')).sort.each do |file|
    path = File.expand_path(file)
    next if File.basename(file) == 'const.rb'
    next if loaded_geometry[path]

    require file
  end
end
