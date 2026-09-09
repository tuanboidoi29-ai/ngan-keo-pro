# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module TT
  module NganKeo
    EXTENSION = SketchupExtension.new('TT - ngan keo', 'tt_ngan_keo/main')
    EXTENSION.version = '1.1.1'
    EXTENSION.creator = 'TRẦN TUẤN'
    EXTENSION.description = 'Quản lý ngăn kéo trong SketchUp.'

    # true chỉ nạp mã extension; cửa sổ chỉ mở từ callback của command.
    Sketchup.register_extension(EXTENSION, true)
  end
end