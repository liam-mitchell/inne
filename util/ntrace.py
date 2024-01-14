import matplotlib.pyplot as mpl
from matplotlib.animation import FFMpegWriter
#mpl.rcParams["animation.ffmpeg_path"] = "C:\\Users\\Utilisateur\\Desktop\\BizHawk-2.8-win-x64\\dll\\ffmpeg.exe"
import math
import os.path
import zlib


outte_mode = True #Only set to False when manually running the script. Changes what the output of the tool is.
compressed_inputs = True #Only set to False when manually running the script and using regular uncompressed input files.
animation_mode = False #Experimental animated plot, set to false for now in outte

#Required names for files. Only change values if running manually.
raw_inputs_0 = "inputs_0"
raw_inputs_1 = "inputs_1"
raw_inputs_2 = "inputs_2"
raw_inputs_3 = "inputs_3"
raw_map_data = "map_data"
raw_inputs_episode = "inputs_episode"
raw_map_data_0 = "map_data_0"
raw_map_data_1 = "map_data_1"
raw_map_data_2 = "map_data_2"
raw_map_data_3 = "map_data_3"
raw_map_data_4 = "map_data_4"
map_img = None #This one is only needed for manual execution

#Import inputs.
inputs_list = []
if os.path.isfile(raw_inputs_episode):
    tool_mode = "splits"
    with open(raw_inputs_episode, "rb") as f:
        inputs_episode = zlib.decompress(f.read()).split(b"&")
        for inputs_level in inputs_episode:
            inputs_list.append([int(b) for b in inputs_level])
else:
    tool_mode = "trace"
if os.path.isfile(raw_inputs_0):
    with open(raw_inputs_0, "rb") as f:
        if compressed_inputs:
            inputs_list.append([int(b) for b in zlib.decompress(f.read())])
        else:
            inputs_list.append([int(b) for b in f.read()][215:])
if os.path.isfile(raw_inputs_1):
    with open(raw_inputs_1, "rb") as f:
        if compressed_inputs:
            inputs_list.append([int(b) for b in zlib.decompress(f.read())])
        else:
            inputs_list.append([int(b) for b in f.read()][215:])
if os.path.isfile(raw_inputs_2):
    with open(raw_inputs_2, "rb") as f:
        if compressed_inputs:
            inputs_list.append([int(b) for b in zlib.decompress(f.read())])
        else:
            inputs_list.append([int(b) for b in f.read()][215:])
if os.path.isfile(raw_inputs_3):
    with open(raw_inputs_3, "rb") as f:
        if compressed_inputs:
            inputs_list.append([int(b) for b in zlib.decompress(f.read())])
        else:
            inputs_list.append([int(b) for b in f.read()][215:])

#import map data
mdata_list = []
if tool_mode == "trace":
    with open(raw_map_data, "rb") as f:
        mdata = [int(b) for b in f.read()]
    for i in range(len(inputs_list)):
        mdata_list.append(mdata)
elif tool_mode == "splits":
    with open(raw_map_data_0, "rb") as f:
        mdata_list.append([int(b) for b in f.read()])
    with open(raw_map_data_1, "rb") as f:
        mdata_list.append([int(b) for b in f.read()])
    with open(raw_map_data_2, "rb") as f:
        mdata_list.append([int(b) for b in f.read()])
    with open(raw_map_data_3, "rb") as f:
        mdata_list.append([int(b) for b in f.read()])
    with open(raw_map_data_4, "rb") as f:
        mdata_list.append([int(b) for b in f.read()])

#Defining physics constants
gravity = 0.06666666666666665
gravity_held = 0.01111111111111111
ground_accel = 0.06666666666666665
air_accel = 0.04444444444444444
drag = 0.9933221725495059 # 0.99^(2/3)
friction_ground = 0.9459290248857720 # 0.92^(2/3)
friction_ground_slow = 0.8617738760127536 # 0.80^(2/3)
friction_wall = 0.9113380468927672 # 0.87^(2/3)
max_xspeed = 3.333333333333333
max_jump_duration = 45

class Ninja:
    """This class is responsible for updating and storing the positions and velocities of each ninja.
    self.poslog contains all the coordinates used to generate the traces of the replays.
    """
    def __init__(self, xspawn, yspawn):
        """Initiate ninja position at spawn point, and initiate other values to their initial state"""
        self.xpos = xspawn
        self.ypos = yspawn
        self.xspeed = 0
        self.yspeed = 0
        self.applied_gravity = gravity
        self.applied_friction = friction_ground
        self.state = 4
        self.radius = 10
        self.hor_input = 0
        self.jump_input = 0
        self.jump_input_old = 0
        self.jump_duration = 0
        self.jump_buffer = 0
        self.floor_buffer = 0
        self.wall_buffer = 0
        self.floor_jumping = False
        self.wall_jumping = False
        self.poslog = [(0, xspawn, yspawn)]
        self.xposlog = [xspawn]
        self.yposlog = [yspawn]
        self.speedlog = [(0,0,0)]
        self.plog = [(0,0)]

    def center_cell(self):
        """find the cell coordinates containing the center of the ninja at its current x and y pos"""
        return (math.floor(self.xpos / 24), math.floor(self.ypos / 24))
    
    def neighbour_cells(self, radius):
        """Return a set containing all cells that the ninja overlaps.
        There can be either 1, 2 or 4 cells in the neighbourhood
        """
        x_lower = math.floor((self.xpos - radius) / 24)
        x_upper = math.floor((self.xpos + radius) / 24)
        y_lower = math.floor((self.ypos - radius) / 24)
        y_upper = math.floor((self.ypos + radius) / 24)
        cell_set = set()
        cell_set.add((x_lower, y_lower))
        cell_set.add((x_lower, y_upper))
        cell_set.add((x_upper, y_lower))
        cell_set.add((x_upper, y_upper))
        return cell_set
    
    def object_neighbour_cells(self):
        """Return a list that contains all the cells that could contain objects which the ninja could interact with.
        This list contains nine cells. The one containing the center of the ninja and the eight cells around it.
        """
        center_cell = self.center_cell()
        center_x = center_cell[0]
        center_y = center_cell[1]
        cell_list = [center_cell]
        cell_list.append((center_x-1,center_y-1))
        cell_list.append((center_x,center_y-1))
        cell_list.append((center_x+1,center_y-1))
        cell_list.append((center_x-1,center_y))
        cell_list.append((center_x+1,center_y))
        cell_list.append((center_x-1,center_y+1))
        cell_list.append((center_x,center_y+1))
        cell_list.append((center_x+1,center_y+1))
        return cell_list
    
    def integrate(self):
        self.xspeed *= drag
        self.yspeed *= drag
        self.yspeed += self.applied_gravity
        self.xpos_old = self.xpos
        self.ypos_old = self.ypos
        self.xpos += self.xspeed
        self.ypos += self.yspeed

    def pre_collision(self):
        self.xspeed_old = self.xspeed
        self.yspeed_old = self.yspeed
        self.floor_count = 0
        self.wall_count = 0
        self.floor_normal_x = 0
        self.floor_normal_y = 0

    def collide_vs_objects(self):
        neighbour_cells = self.object_neighbour_cells()
        for cell in neighbour_cells:
            for entity in entity_dic[cell]:
                if entity.is_physical_collidable and entity.active:
                    depen = entity.physical_collision(self, self.radius)
                    if depen:
                        depen_x = depen[0]
                        depen_y = depen[1]
                        self.xpos += depen_x
                        self.ypos += depen_y
                        self.xspeed += depen_x
                        self.yspeed += depen_y
                        if depen_y < 0:
                            self.floor_count += 1
                            self.floor_normal_x += depen_x
                            self.floor_normal_y += depen_y

    def collide_vs_tiles(self):
        for point in range(32):
            closest_point = get_single_closest_point(self)
            if not closest_point:
                break
            a = closest_point[0]
            b = closest_point[1]
            dx = self.xpos - a
            dy = self.ypos - b
            dist = math.sqrt(dx**2 + dy**2)
            if dist == 0:
                break
            xpos_new = a + self.radius*dx/dist
            ypos_new = b + self.radius*dy/dist
            self.xpos = xpos_new
            self.ypos = ypos_new
            dot_product = self.xspeed * dx + self.yspeed * dy
            if dot_product < 0: #check if you're moving towards the corner.
                xspeed_new = (self.xspeed*dy - self.yspeed*dx) / dist**2 * dy
                yspeed_new = (self.xspeed*dy - self.yspeed*dx) / dist**2 * (-dx)
                self.xspeed = xspeed_new
                self.yspeed = yspeed_new
            if dy < -0.0001:
                self.floor_count += 1
                self.floor_normal_x += dx
                self.floor_normal_y += dy

    def post_collision(self):
        #Perform LOGICAL collisions between the ninja and nearby entities.
        neighbour_cells = self.object_neighbour_cells()
        for cell in neighbour_cells:
            for entity in entity_dic[cell]:
                if entity.is_logical_collidable and entity.active:
                    entity.logical_collision(self, self.radius + 0.1)

        #Check if the ninja can interact with nearby walls.
        neighbour_cells = self.neighbour_cells(self.radius + 0.1)
        for cell in neighbour_cells:
            for segment in segment_dic[cell]:
                if segment.active and segment.type == "linear":
                    wall_normal = segment.wall_intersecting(self)
                    if wall_normal:
                        self.wall_count += 1
                        self.wall_normal = wall_normal

        #Calculate the combined floor normalized normal vector if the ninja has touched any floor.
        if self.floor_count > 0:
            floor_scalar = math.sqrt(self.floor_normal_x**2 + self.floor_normal_y**2)
            if floor_scalar == 0:
                self.floor_normalized_x = 0
                self.floor_normalized_y = -1
            else:
                self.floor_normalized_x = self.floor_normal_x/floor_scalar
                self.floor_normalized_y = self.floor_normal_y/floor_scalar

    def floor_jump(self):
        self.state = 3
        self.applied_gravity = gravity_held
        if self.floor_normalized_x == 0:
            jx = 0
            jy = -2
        else:
            dx = self.floor_normalized_x
            dy = self.floor_normalized_y
            if self.xspeed * dx > 0:
                if self.xspeed * self.hor_input >= 0:
                    jx = 2/3 * dx
                    jy = 2 * dy
                else:
                    jx = 0
                    jy = -1.4
            elif self.xspeed * dx < 0:
                if self.xspeed * self.hor_input > 0:
                    jx = 0
                    jy = -1.4
                else:
                    self.xspeed = 0
                    jx = 2/3 * dx
                    jy = 2 * dy
        if self.yspeed > 0:
            self.yspeed = 0
        self.xspeed += jx
        self.yspeed += jy
        self.xpos += jx
        self.ypos += jy
        self.jump_buffer = 0
        self.jump_duration = 0

    def wall_jump(self):
        if self.hor_input * self.wall_normal < 0 and self.state == 5:
            jx = 2/3
            jy = -1
        else:
            jx = 1
            jy = -1.4
        self.state = 3
        self.applied_gravity = gravity_held
        if self.xspeed * self.wall_normal < 0:
            self.xspeed = 0
        if self.yspeed > 0:
            self.yspeed = 0
        self.xspeed += jx * self.wall_normal
        self.yspeed += jy
        self.xpos += jx * self.wall_normal
        self.ypos += jy
        self.jump_buffer = 0
        self.jump_duration = 0
        return  

    def think(self):
        #Start by updating buffers
        if frame == 188:
            print("debug")
        if self.jump_buffer:
            self.jump_buffer -= 1
        if self.floor_buffer:
            self.floor_buffer -= 1
        if self.wall_buffer:
            self.wall_buffer -= 1
        if self.jump_input and not self.jump_input_old:
            self.jump_buffer = 5
        self.jump_input_old = self.jump_input
        if self.floor_count:
            self.floor_buffer = 5
        if self.wall_count:
            self.wall_buffer = 5

        #Determine if the ninja is capable of jumping on that frame
        self.floor_jumping = True if self.jump_buffer and self.floor_buffer else False
        self.wall_jumping = True if self.jump_buffer and self.wall_buffer else False

        #This block deals with the case where the ninja is touching a floor
        if self.floor_count: 
            xspeed_new = self.xspeed + ground_accel * self.hor_input
            if abs(xspeed_new) < max_xspeed:
                self.xspeed = xspeed_new
            if self.state > 2:
                if self.xspeed * self.hor_input <= 0:
                    if self.state == 3:
                        self.applied_gravity = gravity
                    self.state = 2
                else:
                    if self.state == 3:
                        self.applied_gravity = gravity
                    self.state = 1
            if not self.floor_jumping:
                if self.state == 2:
                    projection = abs(self.yspeed * self.floor_normalized_x - self.xspeed * self.floor_normalized_y)
                    if self.hor_input * projection * self.xspeed > 0:
                        self.state = 1
                        return
                    if projection < 0.1 and self.floor_normalized_x == 0:
                        self.state = 0
                        return
                    if self.yspeed < 0 and self.floor_normalized_x != 0:
                        #Up slope friction formula, very dumb but that's how it is
                        speed_scalar = math.sqrt(self.xspeed**2 + self.yspeed**2)
                        fric_force = abs(self.xspeed * (1-friction_ground) * self.floor_normalized_y)
                        fric_force2 = speed_scalar - fric_force * self.floor_normalized_y**2
                        self.xspeed = self.xspeed / speed_scalar * fric_force2
                        self.yspeed = self.yspeed / speed_scalar * fric_force2 
                        return
                    self.xspeed *= friction_ground
                    return
                if self.state == 1:
                    projection = abs(self.yspeed * self.floor_normalized_x - self.xspeed * self.floor_normalized_y)
                    if self.hor_input * projection * self.xspeed > 0:
                        if self.hor_input * self.floor_normalized_x >= 0: #if holding inputs in downhill direction or flat ground
                            return
                        if abs(xspeed_new) < max_xspeed:
                            boost = ground_accel/2 * self.hor_input
                            xboost = boost * self.floor_normalized_y * self.floor_normalized_y
                            yboost = boost * self.floor_normalized_y * -self.floor_normalized_x
                            self.xspeed += xboost
                            self.yspeed += yboost
                        return
                    self.state = 2
                else: #if you were in state 0 I guess
                    if self.hor_input:
                        self.state = 1
                        return
                    projection = abs(self.yspeed * self.floor_normalized_x - self.xspeed * self.floor_normalized_y)
                    if projection < 0.1:
                        self.xspeed *= friction_ground_slow
                        return
                    self.state = 2
                    return

        #This block deals with the case where the ninja didn't touch a floor
        if not self.floor_count:
            xspeed_new = self.xspeed + air_accel * self.hor_input
            if abs(xspeed_new) < max_xspeed:
                self.xspeed = xspeed_new
            if self.state < 3:
                self.state = 4
                return
            if self.state == 3:
                self.jump_duration += 1
                if self.jump_input == 0 or self.jump_duration > max_jump_duration:
                    self.applied_gravity = gravity
                    self.state = 4
                return
            if not self.wall_jumping:
                if not self.wall_count:
                    self.state = 4
                else:
                    if self.state == 5:
                        if self.hor_input * self.wall_normal <= 0:
                            self.yspeed *= friction_wall
                        else:
                            self.state = 4
                    else:
                        if self.yspeed > 0 and self.hor_input * self.wall_normal < 0:
                            self.state = 5

        #Deals with jumping     
        if self.floor_jumping and self.floor_count:
            self.floor_jump()
            return
        if self.wall_jumping:
            self.wall_jump()
            return
        if self.floor_jumping and not self.floor_count:
            self.floor_jump()

class GridSegmentLinear:
    """Contains all the linear segments of tiles and doors that the ninja can interract with"""
    def __init__(self, p1, p2):
        """Initiate an instance of a linear segment of a tile. 
        Each segment is defined by the coordinates of its two end points.
        """
        self.x1 = p1[0]
        self.y1 = p1[1]
        self.x2 = p2[0]
        self.y2 = p2[1]
        self.active = True
        self.type = "linear"

    def collision_check(self, ninja):
        """Check if the ninja is interesecting with the segment.
        If so, calculate the penetration length and the closest point on the segment from the center of the ninja.
        """
        px = self.x2 - self.x1
        py = self.y2 - self.y1
        seg_lensq = px**2 + py**2
        u = ((ninja.xpos-self.x1)*px + (ninja.ypos-self.y1)*py)/seg_lensq
        u = max(u, 0)
        u = min(u, 1)
        x = self.x1 + u*px
        y = self.y1 + u*py
        dist = math.sqrt((ninja.xpos-x)**2 + (ninja.ypos-y)**2)
        penetration = ninja.radius - dist if dist < 9.9999999 else 0
        return (x, y), penetration
    
    def wall_intersecting(self, ninja):
        """Return True only if the segment is a wall that is intersecting the ninja with an increased radius of 10.1
        Also store the wall normal into the ninja's wall_normal variable"""
        if self.x1 == self.x2:
            if -(ninja.radius + 0.1) < ninja.xpos-self.x1 < 0 and self.y1 <= ninja.ypos <= self.y2:
                return -1
            if 0 < ninja.xpos-self.x1 < (ninja.radius + 0.1) and self.y1 <= ninja.ypos <= self.y2:
                return 1
    
class GridSegmentCircular:
    """Contains all the circular segments of tiles that the ninja can interract with"""
    def __init__(self, center, quadrant, convex=True, radius=24):
        """Initiate an instance of a circular segment of a tile. 
        Each segment is defined by the coordinates of its center, a vector indicating which
        quadrant contains the qurater-circle, a boolean indicating if the tile is convex or
        concave, and the radius of the quarter-circle.
        """
        self.xpos = center[0]
        self.ypos = center[1]
        self.hor = quadrant[0]
        self.ver = quadrant[1]
        self.active = True
        self.type = "circular"
        self.radius = radius
        self.convex = convex

    def collision_check(self, ninja):
        """Check if the ninja is interesecting with the segment.
        If so, calculate the penetration length and the closest point on the segment from the center of the ninja.
        """
        dx = ninja.xpos - self.xpos
        dy = ninja.ypos - self.ypos
        dist = math.sqrt(dx**2 + dy**2)
        x = self.xpos + self.radius * dx / dist
        y = self.ypos + self.radius * dy / dist
        if self.convex:
            penetration = ninja.radius + self.radius - dist
        else:
            penetration = dist + ninja.radius - self.radius
        if not (dx * self.hor > 0 and dy * self.ver > 0) or penetration < 0.0000001:
            penetration = 0
        return (x, y), penetration

class Entity:
    """Class that all entity types (gold, bounce blocks, thwumps, etc.) inherit from."""
    def __init__(self, type, xcoord, ycoord):
        """Inititate a member from map data"""
        self.type = type
        self.xpos = xcoord*6
        self.ypos = ycoord*6
        self.active = True
        self.is_logical_collidable = False
        self.is_physical_collidable = False
        self.is_movable = False
        self.is_thinkable = False
        self.cell = (math.floor(self.xpos / 24), math.floor(self.ypos / 24))
        entity_dic[self.cell].append(self)
        entity_list.append(self)

    def is_colliding_circle(self, ninja, radius):
        """Returns True if the ninja is colliding with the entity. That is, if the distance
        between the center of the ninja and the center of the entity is inferior to the lenth of the
        entity's radius plus the ninja's radius.
        """
        dx = self.xpos - ninja.xpos
        dy = self.ypos - ninja.ypos
        dist = math.sqrt(dx**2 + dy**2)
        return dist < self.radius + radius
    
    def grid_move(self):
        """As the entity is moving, if its center goes from one grid cell to another,
        remove it from the previous cell and insert it into the new cell.
        """
        entity_dic[self.cell].remove(self)
        self.cell = (math.floor(self.xpos / 24), math.floor(self.ypos / 24))
        entity_dic[self.cell].append(self)

class EntityMine(Entity):
    def __init__(self, type, xcoord, ycoord):
        super().__init__(type, xcoord, ycoord)
        self.radius = 4
        self.color = "#910A46"

class EntityGold(Entity):
    def __init__(self, type, xcoord, ycoord):
        super().__init__(type, xcoord, ycoord)
        self.is_logical_collidable = True
        self.radius = 6
        self.collected = False
        self.color = "#EDDC54"
        
    def logical_collision(self, ninja, radius):
        """If the ninja is colliding with the piece of gold, flag it as being collected."""
        if self.is_colliding_circle(ninja, radius):
            self.collected = frame
            self.active = False

class EntityExit(Entity):
    def __init__(self, type, xcoord, ycoord):
        super().__init__(type, xcoord, ycoord)
        self.is_logical_collidable = True
        self.radius = 12
        self.open = False
        self.ninja_exit = []

    def logical_collision(self, ninja, radius):
        """If the ninja is colliding with the open door, store the frame at which the collision happened"""
        if self.open:
            if self.is_colliding_circle(ninja, radius):
                self.ninja_exit.append(frame)
                self.active = False

class EntityExitSwitch(Entity):
    def __init__(self, type, xcoord, ycoord, parent):
        super().__init__(type, xcoord, ycoord)
        self.is_logical_collidable = True
        self.radius = 6
        self.collected = False
        self.parent = parent

    def logical_collision(self, ninja, radius):
        """If the ninja is colliding with the switch, flag it as being collected, and open its associated door."""
        if self.is_colliding_circle(ninja, radius):
            self.collected = True
            self.active = False
            self.parent.open = True

class EntityDoorBase(Entity):
    def __init__(self, type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord):
        super().__init__(type, xcoord, ycoord)
        self.is_logical_collidable = True
        self.open = False
        self.sw_xpos = 6 * sw_xcoord
        self.sw_ypos = 6 * sw_ycoord
        if orientation == 0:
            self.segment = GridSegmentLinear((self.xpos, self.ypos-12), (self.xpos, self.ypos+12))
        if orientation == 2:
            self.segment = GridSegmentLinear((self.xpos-12, self.ypos), (self.xpos+12, self.ypos))
        segment_dic[self.cell].append(self.segment)
        self.xpos = self.sw_xpos
        self.ypos = self.sw_ypos
        self.grid_move()

    def change_state(self, open=True):
        #Change the state of the door from closed to open or from open to closed.
        if open:
            self.open = True
            self.segment.active = False
        else:
            self.open = False
            self.segment.active = True

class EntityDoorRegular(EntityDoorBase):
    def __init__(self, type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord):
        super().__init__(type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord)
        self.is_thinkable = True
        self.radius = 10
        self.open_timer = 0

    def think(self):
        #If the door has been opened for more than 5 frames without being touched by the ninja, close it.
        if self.open:
            self.open_timer += 1
            if self.open_timer > 5:
                self.change_state(open=False)

    def logical_collision(self, ninja, radius):
        #If the ninja touches the activation region of the door, open it.
        if self.is_colliding_circle(ninja, radius):
            self.change_state()
            self.open_timer = 0

class EntityDoorLocked(EntityDoorBase):
    def __init__(self, type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord):
        super().__init__(type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord)
        self.radius = 5

    def logical_collision(self, ninja, radius):
        #If the ninja collects the associated open switch, open the door.
        if self.is_colliding_circle(ninja, radius):
            self.change_state()
            self.active = False

class EntityDoorTrap(EntityDoorBase):
    def __init__(self, type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord):
        super().__init__(type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord)
        self.radius = 5
        self.open = True
        self.segment.active = False

    def logical_collision(self, ninja, radius):
        #If the ninja collects the associated close switch, close the door.
        if self.is_colliding_circle(ninja, radius):
            self.change_state(open=False)
            self.active = False
            
class EntityBounceBlock(Entity):
    def __init__(self, type, xcoord, ycoord):
        super().__init__(type, xcoord, ycoord)
        self.is_physical_collidable = True
        self.is_logical_collidable = True
        self.is_movable = True
        self.is_thinkable = True
        self.xspeed = 0
        self.yspeed = 0
        self.xorigin = self.xpos
        self.yorigin = self.ypos
        self.semiside = 9
        self.stiffness = 0.02222222222222222
        self.dampening = 0.98
        self.strength = 0.2
        self.is_immobile = True
        self.log = [(self.xpos, self.ypos)]
        
    def move(self, ninja):
        """Update the position and speed of the bounce block by applying the spring force and dampening."""
        if not self.is_immobile:
            self.xspeed *= self.dampening
            self.yspeed *= self.dampening
            self.xpos += self.xspeed
            self.ypos += self.yspeed
            xforce = self.stiffness * (self.xorigin - self.xpos)
            yforce = self.stiffness * (self.yorigin - self.ypos)
            self.xpos += xforce
            self.ypos += yforce
            self.xspeed += xforce
            self.yspeed += yforce
            self.grid_move()

    def think(self):
        """If the bounce block has low speed and small distance from its origin,
        set its position to the origin, set its speed to 0, and flag it as immobile.
        """
        if not self.is_immobile:
            if (self.xspeed**2 + self.yspeed**2) < 0.05 and ((self.xpos - self.xorigin)**2 + (self.ypos - self.yorigin)**2) < 0.05:
                self.xpos = self.xorigin
                self.ypos = self.yorigin
                self.xspeed = 0
                self.yspeed = 0
                self.is_immobile = True

    def physical_collision(self, ninja, radius):
        #Collide with the ninja. 
        depen = collision_square_vs_point((self.xpos, self.ypos), (ninja.xpos, ninja.ypos), self.semiside + radius)
        depen_x = depen[0]
        depen_y = depen[1]
        depen_len = abs(depen_x) + abs(depen_y)
        if depen_len > 0:
            self.xpos -= depen_x * (1-self.strength)
            self.ypos -= depen_y * (1-self.strength)
            self.xspeed -= depen_x * (1-self.strength)
            self.yspeed -= depen_y * (1-self.strength)
            self.is_immobile = False
            return (depen_x * self.strength, depen_y*self.strength)
        
    def logical_collision(self, ninja, radius):
        #Check if the ninja can interact with the wall of the bounce block
        depen = collision_square_vs_point((self.xpos, self.ypos), (ninja.xpos, ninja.ypos), self.semiside + radius)
        depen_x = depen[0]
        if depen_x:
            ninja.wall_count += 1
            ninja.wall_normal = depen_x / abs(depen_x)

class EntityBoostPad(Entity):
    def __init__(self, type, xcoord, ycoord):
        super().__init__(type, xcoord, ycoord)
        self.is_movable = True
        self.radius = 6
        self.is_touching_ninja = False

    def move(self, ninja):
        #If the ninja starts touching the booster, add 2 to its velocity norm.
        if self.is_colliding_circle(ninja, ninja.radius):
            if not self.is_touching_ninja:
                vel_norm = math.sqrt(ninja.xspeed**2 + ninja.yspeed**2)
                if vel_norm > 0:
                    x_boost = 2 * ninja.xspeed/vel_norm
                    y_boost = 2 * ninja.yspeed/vel_norm
                    ninja.xspeed += x_boost
                    ninja.yspeed += y_boost
                self.is_touching_ninja = True
        else:
            self.is_touching_ninja = False

def get_single_closest_point(p):
    neighbour_cells = p.neighbour_cells(p.radius)
    biggest_penetration = 0
    for cell in neighbour_cells:
        for segment in segment_dic[cell]:
            if segment.active:
                point, penetration = segment.collision_check(p)
                if penetration > biggest_penetration:
                    biggest_penetration = penetration
                    closest_point = point
    if biggest_penetration > 0:
        return closest_point

def collision_square_vs_point(square_pos, point_pos, semiside):
    """Return the depenetration vector to depenetrate a point out of a square.
    Used to collide the ninja with square entities. (bounce blocks, thwumps, shwumps)"""
    x0 = square_pos[0]
    y0 = square_pos[1]
    x1 = point_pos[0]
    y1 = point_pos[1]
    dx = x1 - x0
    dy = y1 - y0
    penx = semiside - abs(dx)
    peny = semiside - abs(dy)
    if  penx > 0 and peny > 0:
        if peny <= penx:
            return (0, -peny) if dy < 0 else (0, peny)
        return (-penx, 0) if dx < 0 else (penx, 0)
    return (0, 0)
          
def tick(p, frame):
    """This is the main function that handles physics.
    This function gets called once per frame.
    """
    #Extract inputs for this frame.
    p.hor_input = hor_inputs[frame-1]
    p.jump_input = jump_inputs[frame-1]

    #Move all movable entities.
    for entity in entity_list:
        if entity.is_movable and entity.active:
            entity.move(p)

    #Make all thinkable entities think.
    for entity in entity_list:
        if entity.is_thinkable and entity.active:
            entity.think()
            
    #Do pre collision calculations.
    p.integrate()
    p.pre_collision()

    #Handle PHYSICAL collisions with entities.
    p.collide_vs_objects()

    #Handle physical collisions with tiles.
    p.collide_vs_tiles()

    #Do post collision calculations.
    p.post_collision()

    #Make ninja think
    p.think()

    #Update all the logs for debugging purposes. Only the position log will be used to draw the route.
    p.poslog.append((frame, round(p.xpos, 6), round(p.ypos, 6)))
    p.speedlog.append((frame, round(p.xspeed, 6), round(p.yspeed, 6)))
    p.xposlog.append(p.xpos)
    p.yposlog.append(p.ypos)

#extract horizontal arrows inputs, jump inputs, and replay length from the inputs
hor_inputs_dic = {0:0, 1:0, 2:1, 3:1, 4:-1, 5:-1, 6:-1, 7:-1}
jump_inputs_dic = {0:0, 1:1, 2:0, 3:1, 4:0, 5:1, 6:0, 7:1}

xposlog = []
yposlog = []
goldlog = []
frameslog = []
validlog = []

#Repeat this loop for each individual replay
for i in range(len(inputs_list)):
    #Extract inputs and map data from the list
    inputs = inputs_list[i]
    mdata = mdata_list[i]

    #Convert inputs in a more useful format.
    hor_inputs = [hor_inputs_dic[inp] for inp in inputs]
    jump_inputs = [jump_inputs_dic[inp] for inp in inputs]
    inp_len = len(inputs)

    #extract tile data from map data
    tile_data = mdata[184:1150]

    #initiate a dictionary mapping each tile to its cell. Start by filling it with full tiles.
    tile_dic = {}
    for x in range(44):
        for y in range(25):
            tile_dic[(x, y)] = 1

    #map each tile to its cell
    for x in range(42):
        for y in range(23):
            tile_dic[(x+1, y+1)] = tile_data[x + y*42]

    #Initiate dictionaries and list containing interactable segments and entities
    segment_dic = {}
    for x in range(44):
        for y in range(25):
            segment_dic[(x, y)] = []
    entity_dic = {}
    for x in range(44):
        for y in range(25):
            entity_dic[(x, y)] = []
    entity_list = []

    #put each segment in its correct cell
    for coord, tile_id in tile_dic.items():
        xtl = coord[0] * 24
        ytl = coord[1] * 24
        if tile_id == 1: #1: full tile
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+24)))
        if tile_id == 2: #2-5: half tiles
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+12), (xtl+24, ytl+12)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+12)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+12)))
        if tile_id == 3:
            segment_dic[coord].append(GridSegmentLinear((xtl+12, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl+12, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+12, ytl), (xtl+12, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+24)))
        if tile_id == 4:
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+12), (xtl+24, ytl+12)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+12), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl+12), (xtl+24, ytl+24)))
        if tile_id == 5:
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+12, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+12, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+12, ytl), (xtl+12, ytl+24)))
        if tile_id == 6: #6-9: 45 degreee slopes
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl)))
        if tile_id == 7: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl+24)))
        if tile_id == 8: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl)))
        if tile_id == 9: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl+24)))
        if tile_id == 10: #10-13: quarter moons
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentCircular((xtl, ytl), (1, 1)))
        if tile_id == 11: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentCircular((xtl+24, ytl), (-1, 1)))
        if tile_id == 12: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentCircular((xtl+24, ytl+24), (-1, -1)))
        if tile_id == 13: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentCircular((xtl, ytl+24), (1, -1)))
        if tile_id == 14: #14-17: quarter pipes
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentCircular((xtl+24, ytl+24), (-1, -1), convex=False))
        if tile_id == 15: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentCircular((xtl, ytl+24), (1, -1), convex=False))
        if tile_id == 16: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentCircular((xtl, ytl), (1, 1), convex=False))
        if tile_id == 17: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentCircular((xtl+24, ytl), (-1, 1), convex=False))
        if tile_id == 18: #18-21: short mild slopes
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+12)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+12), (xtl+24, ytl)))
        if tile_id == 19:
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+12)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl+12)))
        if tile_id == 20: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl+12), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+12)))
        if tile_id == 21: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+12), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+12), (xtl+24, ytl+24)))
        if tile_id == 22: #22-25: raised mild slopes
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+12)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+12)))
        if tile_id == 23:
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+12)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+12), (xtl+24, ytl+24)))
        if tile_id == 24: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+12), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+12), (xtl+24, ytl)))
        if tile_id == 25: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl+12), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl+12)))
        if tile_id == 26: #26-29: short steep slopes
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+12, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+12, ytl)))
        if tile_id == 27: 
            segment_dic[coord].append(GridSegmentLinear((xtl+12, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+12, ytl), (xtl+24, ytl+24)))
        if tile_id == 28: 
            segment_dic[coord].append(GridSegmentLinear((xtl+12, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+12, ytl+24), (xtl+24, ytl)))
        if tile_id == 29: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+12, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+12, ytl+24)))
        if tile_id == 30: #30-33: raised steep slopes
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+12, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+12, ytl+24), (xtl+24, ytl)))
        if tile_id == 31: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl+12, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+12, ytl+24)))
        if tile_id == 32: 
            segment_dic[coord].append(GridSegmentLinear((xtl+12, ytl), (xtl+24, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+24, ytl), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+12, ytl)))
        if tile_id == 33: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+12, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+24)))
            segment_dic[coord].append(GridSegmentLinear((xtl+12, ytl), (xtl+24, ytl+24)))

    #find the spawn position of the ninja
    xspawn = mdata[1231]*6
    yspawn = mdata[1232]*6

    #initiate player 1 instance of Ninja at spawn coordinates
    p1 = Ninja(xspawn, yspawn)

    #Initiate each entity (other than ninjas)
    index = 1230
    exit_door_count = mdata[1156]
    while (True):
        type = mdata[index]
        xcoord = mdata[index+1]
        ycoord = mdata[index+2]
        orientation = mdata[index+3]
        mode = mdata[index+4]
        if type == 1:
            EntityMine(type, xcoord, ycoord)
        if type == 2:
            EntityGold(type, xcoord, ycoord)
        if type == 3:
            parent = EntityExit(type, xcoord, ycoord)
            child_xcoord = mdata[index + 5*exit_door_count + 1]
            child_ycoord = mdata[index + 5*exit_door_count + 2]
            EntityExitSwitch(4, child_xcoord, child_ycoord, parent)
        if type == 5:
            EntityDoorRegular(type, xcoord, ycoord, orientation, xcoord, ycoord)
        if type == 6:
            switch_xcoord = mdata[index + 6]
            switch_ycoord = mdata[index + 7]
            EntityDoorLocked(type, xcoord, ycoord, orientation, switch_xcoord, switch_ycoord)
        if type == 8:
            switch_xcoord = mdata[index + 6]
            switch_ycoord = mdata[index + 7]
            EntityDoorTrap(type, xcoord, ycoord, orientation, switch_xcoord, switch_ycoord)
        if type == 17:
            EntityBounceBlock(type, xcoord, ycoord)
        if type == 24:
            EntityBoostPad(type, xcoord, ycoord)
        index += 5
        if index >= len(mdata):
            break

    #Execute the main physics function once per frame
    for frame in range(1, inp_len+1):
        tick(p1, frame)

    #Append the positions log of each replay
    xposlog.append(p1.xposlog)
    yposlog.append(p1.yposlog)

    #For splits mode, calculate the amount of gold collected for each replay.
    if tool_mode == "splits":
        gold_amount = mdata[1154]
        gold_collected = 0
        for entity in entity_list:
            if entity.type == 2:
                if entity.collected:
                    gold_collected += 1
        goldlog.append((gold_collected, gold_amount))
        frameslog.append(inp_len)

    #Verify for each replay if the run is valid.
    #That is, verify if the ninja collects the switch and enters the door at the end of the replay.
    ninja_exits = []
    for entity in entity_list:
        if entity.type == 3:
            if entity.ninja_exit:
                ninja_exits.append(entity.ninja_exit)
    valid_replay = False
    if len(ninja_exits) == 1:
        if len(ninja_exits[0]) == 1:
            if ninja_exits[0][0] == inp_len:
                valid_replay = True
    validlog.append(valid_replay)

    #Print info useful for debug if in manual mode
    if not outte_mode:
        print(p1.speedlog[0:500])
        print(p1.poslog[0:500])
        print(valid_replay)

#Plot the route. Only ran in manual mode.
if tool_mode == "trace" and outte_mode == False and animation_mode == False:
    if len(inputs_list) >= 4:
        mpl.plot(xposlog[3], yposlog[3], "#910A46")
    if len(inputs_list) >= 3:
        mpl.plot(xposlog[2], yposlog[2], "#4D31AA")
    if len(inputs_list) >= 2:
        mpl.plot(xposlog[1], yposlog[1], "#EADA56")
    mpl.plot(xposlog[0], yposlog[0], "#000000")
    mpl.axis([0, 1056, 600, 0])
    mpl.axis("off")
    ax = mpl.gca()
    ax.set_aspect("equal", adjustable="box")
    if map_img:
        img = mpl.imread(map_img)
        ax.imshow(img, extent=[0, 1056, 600, 0])
    mpl.show()

if tool_mode == "trace" and outte_mode == False and animation_mode == True:
    fig = mpl.figure()
    fig.set_size_inches(484, 275)
    l, = mpl.plot([], [])
    mpl.axis([0, 1056, 600, 0])
    mpl.axis("off")
    ax = mpl.gca()
    ax.set_aspect("equal", adjustable="box")
    if map_img:
        img = mpl.imread(map_img)
        ax.imshow(img, extent=[0, 1056, 600, 0])

    metadata = dict(title="movie", author="simvyo")
    #writer = FFMpegWriter(fps=60, metadata=metadata)

    def assign_circle_patch(entity, center):
        entity.patch = mpl.Circle(center, entity.radius, color = entity.color)
        ax.add_patch(entity.patch)

    def assign_square_patch(entity, center):
        entity.patch = mpl.Rectangle((center[0] - entity.semiside, center[1] - entity.semiside), 2 * entity.semiside, 2 * entity.semiside, color = "black")
        ax.add_patch(entity.patch)
        
    def trace_initialize():
        p1.patch = mpl.Circle((xposlog[0][0], yposlog[0][0]), 10, color = "black")
        ax.add_patch(p1.patch)
        for entity in entity_list:
            if entity.type in (1, 2):
                assign_circle_patch(entity, (entity.xpos, entity.ypos))
            if entity.type == 17:
                assign_square_patch(entity, entity.log[0])

    def trace_update(frame):
        p1.patch.set(center = (xposlog[0][frame], yposlog[0][frame]))
        for entity in entity_list:
            if entity.type == 2:
                if entity.collected == frame:
                    entity.patch.set(visible = False)
            if entity.type == 17:
                entity.patch.set(x = entity.log[frame][0] - entity.semiside)
                entity.patch.set(y = entity.log[frame][1] - entity.semiside)

    #with writer.saving(fig, "simul.MP4", 2):
        #trace_initialize()
        #for i in range(len(xposlog[0])):
            #trace_update(i)
            #writer.grab_frame()
            #print(i)
            
#For each replay, write to file whether it is valid or not, then write the series of coordinates for each frame. Only ran in outte mode and in trace mode.
if tool_mode == "trace" and outte_mode == True:
    with open("output.txt", "w") as f:
        for i in range(len(inputs_list)):
            print(validlog[i], file=f)
            for frame in range(len(xposlog[i])):
                print(round(xposlog[i][frame], 2), round(yposlog[i][frame], 2), file=f)

#Print episode splits and other info to the console. Only ran in manual mode and splits mode.
if tool_mode == "splits" and outte_mode == False:
    print("SI-A-00 0th replay analysis:")
    split = 90*60
    for i in range(5):
        split = split - frameslog[i] + 1 + goldlog[i][0]*120
        split_score = round(split/60, 3)
        print(f"{i}:-- Is replay valid?: {validlog[i]} | Gold collected: {goldlog[i][0]}/{goldlog[i][1]} | Replay length: {frameslog[i]} frames | Split score: {split_score:.3f}")

#For each level of the episode, write to file whether the replay is valid, then write the score split. Only ran in outte mode and in splits mode.
if tool_mode == "splits" and outte_mode == True:
    split = 90*60
    with open("output.txt", "w") as f:
        for i in range(5):
            print(validlog[i], file=f)
            split = split - frameslog[i] + 1 + goldlog[i][0]*120
            print(split, file=f)