class CreateUserlevels < ActiveRecord::Migration[5.1]

  # Turn a little endian binary array into an integer
  def parse_int(bytes)
    if bytes.is_a?(Array) then bytes = bytes.join end
    bytes.unpack('H*')[0].scan(/../).reverse.join.to_i(16)
  end

  # Reformat date strings received by queries to the server
  def format_date(date)
    date.gsub!(/-/,"/")
    date[-6] = " "
    date = date[2..-1]
    date[0..7].split("/").reverse.join("/") + date[-6..-1]
  end

  # Format of query result: Header (48B) + adjacent map headers (44B each) + adjacent map data blocks (variable length).
  # 1) Header format: Date (16B), map count (4B), page (4B), unknown (4B), category (4B), game mode (4B), unknown (12B).
  # 2) Map header format: Map ID (4B), user ID (4B), author name (16B), # of ++'s (4B), date of publishing (16B).
  # 3) Map data block format: Size of block (4B), # of objects (2B), zlib-compressed map data.
  # Uncompressed map data format: Header (30B) + title (128B) + null (18B) + map data (variable).
  # 1) Header format: Unknown (4B), game mode (4B), unknown (4B), user ID (4B), unknown (14B).
  # 2) Map format: Tile data (966B, 1B per tile), object counts (80B, 2B per object type), objects (variable, 5B per object).
  def parse_levels(levels)
    header = {
      date: format_date(levels[0..15].to_s),
      count: parse_int(levels[16..19]),
      page: parse_int(levels[20..23]),
      category: parse_int(levels[28..31]),
      mode: parse_int(levels[32..35])
    }
    # the regex flag "m" is needed so that the global character "." matches the new line character
    # it was hell to debug this!
    maps = levels[48 .. 48 + 44 * header[:count] - 1].scan(/./m).each_slice(44).to_a.map { |h|
      author = h[8..23].join.each_byte.map{ |b| b > 127 ? " ".ord.chr : b.chr }.join.strip # remove non-ASCII chars
      {
        id: parse_int(h[0..3]),
        author_id: author != "null" ? parse_int(h[4..7]) : -1,
        author: author,
        favs: parse_int(h[24..27]),
        date: format_date(h[28..-1].join)
      }
    }
    i = 0
    offset = 48 + header[:count] * 44
    while i < header[:count]
      len = parse_int(levels[offset..offset + 3])
      maps[i][:object_count] = parse_int(levels[offset + 4..offset + 5])
      map = Zlib::Inflate.inflate(levels[offset + 6..offset + len - 1])
      maps[i][:title] = map[30..157].each_byte.map{ |b| (b < 32 || b > 127) ? " ".ord.chr : b.chr }.join.strip
      maps[i][:tiles] = map[176..1141].scan(/./).map{ |b| parse_int(b) }.each_slice(42).to_a
      maps[i][:objects] = map[1222..-1].scan(/./).map{ |b| parse_int(b) }.each_slice(5).to_a
      offset += len
      i += 1
    end
    {header: header, maps: maps}
  end

  def change
    create_table :userlevels do |t|
      t.integer :author_id, index: true
      t.string :author
      t.string :title
      t.integer :favs
      t.string :date

      #t.binary :tiles
      #t.binary :objects
    end

    (0..96).each{ |l|
      levels = parse_levels(File.binread("maps/" + l.to_s))
      levels[:maps].each{ |map|
        Userlevel.create(
          id: map[:id],
          author_id: map[:author_id],
          author: map[:author],
          title: map[:title],
          favs: map[:favs],
          date: map[:date],
          #tiles: map[:tiles],
          #objects: map[:objects]
        )
        puts map[:id]
      }
    }
  end
end
