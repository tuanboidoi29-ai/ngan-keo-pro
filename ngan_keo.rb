#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'

class DrawerManager
  attr_reader :drawers

  def initialize(file = 'ngan_keo_data.json')
    @file = file
    @drawers = load_drawers
  end

  def add(name:, area:, items: [])
    drawer = {
      'id' => next_id,
      'name' => name,
      'area' => area,
      'items' => items,
      'organized' => false,
      'created_at' => timestamp,
      'updated_at' => timestamp
    }
    @drawers << drawer
    save
    drawer
  end

  def update(id, name: nil, area: nil, items: nil)
    drawer = find(id)
    drawer['name'] = name if name
    drawer['area'] = area if area
    drawer['items'] = items if items
    drawer['updated_at'] = timestamp
    save
    drawer
  end

  def reload
    @drawers = load_drawers
  end

  def list(area: nil, query: nil)
    result = @drawers
    result = result.select { |drawer| drawer['area'].casecmp?(area) } if area
    if query
      result = result.select do |drawer|
        searchable = [drawer['name'], drawer['area'], *drawer['items']].join(' ')
        searchable.downcase.include?(query.downcase)
      end
    end
    result
  end

  def organize(id)
    drawer = find(id)
    drawer['organized'] = true
    save
    drawer
  end

  def remove(id)
    drawer = find(id)
    @drawers.delete(drawer)
    save
    drawer
  end

  private

  def timestamp
    Time.now.strftime('%Y-%m-%d %H:%M:%S')
  end

  def find(id)
    drawer = @drawers.find { |entry| entry['id'] == id.to_i }
    raise ArgumentError, "Không tìm thấy ngăn kéo ##{id}" unless drawer

    drawer
  end

  def next_id
    @drawers.map { |drawer| drawer['id'] }.max.to_i + 1
  end

  def load_drawers
    return [] unless File.exist?(@file)

    JSON.parse(File.read(@file))
  rescue JSON::ParserError
    warn "Dữ liệu trong #{@file} không hợp lệ, bắt đầu với danh sách trống."
    []
  end

  def save
    File.write(@file, JSON.pretty_generate(@drawers))
  end
end

def print_drawers(drawers)
  if drawers.empty?
    puts 'Chưa có ngăn kéo nào.'
    return
  end

  drawers.each do |drawer|
    status = drawer['organized'] ? 'đã sắp xếp' : 'cần sắp xếp'
    items = drawer['items'].empty? ? 'chưa có vật dụng' : drawer['items'].join(', ')
    puts "##{drawer['id']} | #{drawer['name']} | #{drawer['area']} | #{status}"
    puts "   Vật dụng: #{items}"
  end
end

options = { items: nil }
parser = OptionParser.new do |opts|
  opts.banner = 'Cách dùng: ruby ngan_keo.rb [lệnh] [tùy chọn]'
  opts.on('--name TEN', 'Tên ngăn kéo') { |value| options[:name] = value }
  opts.on('--area KHU_VUC', 'Khu vực') { |value| options[:area] = value }
  opts.on('--items A,B,C', Array, 'Danh sách vật dụng') { |value| options[:items] = value }
  opts.on('--id ID', Integer, 'Mã ngăn kéo') { |value| options[:id] = value }
  opts.on('--query TU_KHOA', 'Từ khóa tìm kiếm') { |value| options[:query] = value }
end

command = ARGV.shift
parser.parse!(ARGV)
manager = DrawerManager.new

case command
when 'add'
  raise OptionParser::MissingArgument, '--name và --area là bắt buộc' unless options[:name] && options[:area]

  drawer = manager.add(name: options[:name], area: options[:area], items: options[:items])
  puts "Đã tạo ngăn kéo ##{drawer['id']}: #{drawer['name']}"
when 'list'
  print_drawers(manager.list(area: options[:area], query: options[:query]))
when 'update'
  raise OptionParser::MissingArgument, '--id là bắt buộc' unless options[:id]
  raise OptionParser::MissingArgument, 'Cần ít nhất một trong --name, --area hoặc --items' unless options[:name] || options[:area] || options[:items]

  drawer = manager.update(
    options[:id],
    name: options[:name],
    area: options[:area],
    items: options[:items]
  )
  puts "Đã cập nhật ngăn kéo ##{drawer['id']}: #{drawer['name']}"
when 'organize'
  raise OptionParser::MissingArgument, '--id là bắt buộc' unless options[:id]

  drawer = manager.organize(options[:id])
  puts "Đã đánh dấu '#{drawer['name']}' là đã sắp xếp."
when 'remove'
  raise OptionParser::MissingArgument, '--id là bắt buộc' unless options[:id]

  drawer = manager.remove(options[:id])
  puts "Đã xóa ngăn kéo '#{drawer['name']}'."
else
  puts parser
  puts '\nLệnh: add, list, update, organize, remove'
end