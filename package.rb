# frozen_string_literal: true

require 'fileutils'

version = '1.3.1'
output = "TT-ngan-keo-#{version}.rbz"
files = [
	'tt_ngan_keo.rb',
	'tt_ngan_keo/main.rb',
	'tt_ngan_keo/board_tool.rb',
	'tt_ngan_keo/drawer_v14.rb',
	'tt_ngan_keo/icons/ngan_keo.svg',
	'tt_ngan_keo/icons/create_drawer.svg',
	'tt_ngan_keo/icons/update.svg',
	'update.json'
]

FileUtils.rm_f(output)
system('zip', '-q', output, *files) || abort('Không thể tạo file RBZ. Hãy cài lệnh zip.')
puts "Đã tạo #{output}"