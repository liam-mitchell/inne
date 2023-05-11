require 'byebug'
require 'fileutils'
#require 'tk'
require 'win32/registry'

MAPPACK = 'Classic'
AUTHOR = 'NateyPooPoo'
NAME = 'cla'
HOST = 'https://dojo.nplusplus.ninja'
PORT = 8126
PROXY = '45.32.150.168'
TARGET = "#{PROXY}:#{PORT}/#{NAME}".ljust(HOST.length, "\x00")
DIALOG = true
PAD = 30

def dialog(title, text)
  print "\a"
  type = title == 'Error!' ? 16 : 0
  File.binwrite('tmp.vbs', %{x=msgbox("#{text.split("\n")[0]}", #{type}, "#{title}")})
  spawn "wscript //nologo tmp.vbs & del tmp.vbs" if DIALOG
end

def log_exception(e, msg)
  str1 = "ERROR! Failed to #{$installed ? 'uninstall' : 'install'} '#{MAPPACK}' N++ mappack :("
  str2 = "See the console for details"
  print "\n\n#{str1}\n\n"
  puts "#{msg}\nDetails: #{e}"
  dialog('Error', "#{str1}\" & vbCrLf & vbCrLf & \"#{str2}") if DIALOG
  exit
end

def find_steam_folders(output = true)
  print "┣━ Finding Steam folder... ".ljust(PAD, ' ') if output
  # Find Steam directory in the registry
  folder = nil
  folder = Win32::Registry::HKEY_LOCAL_MACHINE.open('SOFTWARE\WOW6432Node\Valve\Steam') rescue nil
  folder = (Win32::Registry::HKEY_LOCAL_MACHINE.open('SOFTWARE\Valve\Steam') rescue nil) if folder.nil?
  raise "Steam folder not found in registry" if folder.nil?

  # Find Steam installation path in the registry
  path = folder['InstallPath'] rescue nil
  raise "Steam installation path not found in registry" if path.nil?
  raise "Steam installation not found" if !Dir.exist?(path)

  # Find steamapps folder
  steamapps = File.join(path, 'steamapps')
  raise "Steam folder not found (steamapps folder missing)" if !Dir.exist?(steamapps)
  library = File.read(File.join(steamapps, 'libraryfolders.vdf')) rescue nil
  raise "Steam folder not found (libraryfolders.vdf file missing)" if library.nil?

  # Find alternative Steam installation paths
  folders = library.split("\n").select{ |l| l =~ /"path"/i }.map{ |l| l[/"path".*"(.+)"/, 1].gsub(/\\\\/, '\\') rescue nil }.compact
  folders << path
  folders.uniq!

  puts "OK" if output
  folders
rescue RuntimeError => e
  log_exception('', e)
rescue => e
  log_exception(e, "Failed to find Steam folder")
end

def find_npp_folder(output = true)
  folder = nil
  folders = find_steam_folders(output)
  print "┣━ Finding N++ folder... ".ljust(PAD, ' ') if output
  folders.each{ |f|
    path = File.join(f, 'steamapps', 'common', 'N++')
    folder = path if Dir.exist?(path)
  }
  raise "N++ installation not found" if folder.nil?
  
  puts "OK" if output
  folder
rescue RuntimeError => e
  log_exception('', e)
rescue => e
  log_exception(e, "Failed to find N++ folder.")
end

def find_npp_library(output = true)
  # Read main library file
  folder = find_npp_folder(output)
  print "┣━ Finding npp.dll... ".ljust(PAD, ' ') if output
  fn = File.join(folder, 'npp.dll')
  raise "N++ files not found (npp.dll missing)" if !File.file?(fn)

  puts "OK" if output
  fn
rescue RuntimeError => e
  log_exception('', e)
rescue => e
  log_exception(e, "Failed to find N++ files.")
end

def patch(depatch = false, info = false)
  # Read main library file
  fn = find_npp_library(!info)
  print "┣━ #{depatch ? 'Depatching' : 'Patching'} npp.dll... ".ljust(PAD, ' ') if !info
  file = File.binread(fn)
  return !file[/#{HOST}/] if info

  # Patch library
  raise "Failed to patch N++ files (incorrect target length)" if TARGET.length != HOST.length
  file = depatch ? file.gsub!(TARGET, HOST) : file.gsub!(HOST, TARGET)
  raise "Failed to patch N++ files (host/target not found)" if file.nil?
  File.binwrite(fn, file)

  puts "OK" if !info
rescue RuntimeError => e
  log_exception('', e)
rescue => e
  log_exception(e, "Failed to patch N++ files.")
end

def depatch
  patch(true)
end

def change_levels(install = true)
  print "┣━ Swapping map files#{install ? '' : ' back'}... ".ljust(PAD, ' ')
  # Find folder
  folder = File.join(find_npp_folder(false), 'NPP', 'Levels')
  raise "N++ levels folder not found" if !Dir.exist?(folder)
  
  # Change file
  tmp = $0[/(.*)\//, 1]
  fn = install ? File.join(tmp, 'SI.txt') : File.join(tmp, 'SI_original.txt')
  FileUtils.cp_r(fn, File.join(folder, 'SI.txt'), remove_destination: true)

  puts "OK"
rescue RuntimeError => e
  log_exception('', e)
rescue => e
  log_exception(e, "Failed to change level files.")
end

def change_text(file, name, value)
  file.sub!(/#{name}\|[^\|]+?\|/, "#{name}|#{value}|")
end

def change_texts(install = true)
  print "┣━ Changing texts#{install ? '' : ' back'}... ".ljust(PAD, ' ')
  # Read file
  fn = File.join(find_npp_folder(false), 'NPP', 'loc.txt')
  file = File.binread(fn) rescue nil
  return if file.nil?

  # Change texts
  change_text(file, 'HIGH_SCORE_PANEL_FRIEND_HIGHSCORES_LONG', install ? 'Speedrun Boards' : 'Friends Highscores')
  change_text(file, 'HIGH_SCORE_PANEL_FRIEND_HIGHSCORES_SHORT', install ? 'Speedrun' : 'Friends')

  # Save file
  File.binwrite(fn, file)
  puts "OK"
rescue
  nil
end

def install
  print "\n┏━━━ Installing '#{MAPPACK}' N++ mappack\n┃\n"
  patch
  change_levels(true)
  change_texts(true)
  puts "┃\n┗━━━ Installed '#{MAPPACK}' successfully!\n\n"
  dialog("N++ Mappack", "Installed '#{MAPPACK}' N++ mappack successfully!")
end

def uninstall
  print "\n┏━━━ Uninstalling '#{MAPPACK}' N++ mappack\n┃\n"
  depatch
  change_levels(false)
  change_texts(false)
  puts "┃\n┗━━━ Uninstalled '#{MAPPACK}' successfully!\n\n"
  dialog("N++ Mappack", "Uninstalled '#{MAPPACK}' N++ mappack successfully!")
end

str1 = "   N++ MAPPACK INSTALLER   "
str2 = "   '#{MAPPACK}' by #{AUTHOR}   "
size = [str1.size, str2.size].max
puts
puts "╔#{'═' * size}╗"
puts "║#{str1.center(size)}║"
puts "║#{str2.center(size)}║"
puts "╚#{'═' * size}╝"
puts "Report technical issues to Eddy"
puts
print "Checking current state... "
$installed = patch(false, true)
puts $installed ? 'installed' : 'uninstalled'
$installed ? uninstall : install
gets if !DIALOG

=begin
# Main window
$root = TkRoot.new(title: "")
w, h = 200, 50
$root.minsize(w, h)
$root.geometry("#{w}x#{h}")
$root.grid_columnconfigure(0, weight: 1)
$root.resizable(0, 0)
screen_width = $root.winfo_screenwidth
screen_height = $root.winfo_screenheight
x = (screen_width - w) / 2
y = (screen_height - h) / 2
$root.geometry("#{$root.width}x#{$root.height}+#{x}+#{y}")
Tk.bell

# Elements
label = TkLabel.new($root, text: "#{MAPPACK} #{$installed ? "uninstalled" : "installed"} successfully!").grid(row: 0, column: 0, sticky: 'news')
button = TkButton.new($root, text: "Ok", command: -> { $root.destroy }).grid(row: 1, column: 0)

# Run GUI
Tk.mainloop
=end