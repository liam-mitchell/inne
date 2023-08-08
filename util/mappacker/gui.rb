require 'tk'

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