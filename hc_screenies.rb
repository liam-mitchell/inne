require 'rmagick'
Dir.chdir('screenshots')
files = Dir.entries(Dir.pwd).select{ |f| File.file?(f) }.map{ |f| f[0..-5] }.sort

def ids(tab, offset, n)
  ret = (0..n - 1).to_a.map{ |s|
    tab + "-" + s.to_s.rjust(2,"0")
  }.each_with_index.map{ |l, i| [offset + i, l] }.to_h
end

[['SI', 0, 5], ['S', 24, 20], ['SL', 48, 20], ['SU', 96, 20]].each{ |s|
  ids(s[0],s[1],s[2]).each{ |story|
    images = files.select{ |f|
      parts = f.split('-')
      parts.size == 3 && parts[1] != 'X' &&
      (parts[0] + '-' + parts[2]) == story[1]
    }
    list = Magick::ImageList.new
    images.each{ |f| list.push(Magick::Image.read(f + '.jpg').first) }
    list.append(true).write(story[1] + '.jpg')
    #print(story[1] + ": ")
    #images.each{ |f| print(f + " ") }
    #print("\n")
  }
}
