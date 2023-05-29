import matplotlib.pyplot as mpl
import math
import os.path
import zlib


outte_mode = True #Only set to False when manually running the script. Changes what the output of the tool is.
compressed_inputs = True #Only set to False when manually running the script and using regular uncompressed input files.

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
map_img = "None" #This one is only needed for manual execution

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

#defining physics constants
gravity = 0.06666666666666665
gravity_held = 0.01111111111111111
ground_accel = 0.06666666666666665
air_accel = 0.04444444444444444
drag = 0.9933221725495059 # 0.99^(2/3)
friction_ground = 0.9459290248857720 # 0.92^(2/3)
friction_wall = 0.9113380468927672 # 0.87^(2/3)
max_xspeed = 3.333333333333333 

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
        self.grounded = False
        self.ground_normal = (0, -1)
        self.ground_sliding = 0
        self.walled = False
        self.wall_normal = 0
        self.wall_sliding = 0
        self.pre_buffer = 0
        self.post_buffer = 0
        self.post_buffer_wall = 0
        self.jump_held_time = 0
        self.jumping = False
        self.wall_jumping = False
        self.gravity_held_time = 0
        self.hor_input = 0
        self.jump_input = 0
        self.poslog = [(0, xspawn, yspawn)]
        self.xposlog = [xspawn]
        self.yposlog = [yspawn]
        self.speedlog = [(0,0,0)]
        self.plog = [(0,0)]
        self.radius = 10

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
    
    def pre_collision(self):
        """Update the speeds and positions of the ninja before the collision phase."""
        self.xspeed *= drag
        self.yspeed *= drag
        self.yspeed += self.applied_gravity
        self.xpos += self.xspeed
        self.ypos += self.yspeed
        self.grounded = False
        self.walled = False

        if self.jump_input:
            self.jump_held_time += 1
            if self.jump_held_time == 1:
                self.pre_buffer = 6
            if self.gravity_held_time:
                self.gravity_held_time += 1
        else:
            self.jump_held_time = 0
            self.jumping = False
            self.wall_jumping = False
            self.gravity_held_time = 0

    def ground_jump(self):
        if self.pre_buffer and self.post_buffer in (1, 2, 3, 5) and not self.jumping and not self.wall_jumping:
            if self.ground_normal == (0, -1):
                jx = 0
                jy = -2
            else:
                gnx = self.ground_normal[0]
                gny = self.ground_normal[1]
                if self.xspeed * gnx > 0:
                    if self.xspeed * self.hor_input >= 0:
                        jx = 2/3 * gnx
                        jy = 2 * gny
                    else:
                        jx = 0
                        jy = -1.4
                elif self.xspeed * gnx < 0:
                    if self.xspeed * self.hor_input > 0:
                        jx = 0
                        jy = -1.4
                    else:
                        self.xspeed = 0
                        jx = 2/3 * gnx
                        jy = 2 * gny
            self.xspeed += jx
            self.yspeed = min(self.yspeed, 0)
            self.yspeed += jy
            self.xpos += jx
            self.ypos += jy
            self.jumping = True
            self.gravity_held_time = 1
            self.pre_buffer = 0
            self.post_buffer = 0
            self.grounded = False

    def wall_jump(self):

        if self.pre_buffer and self.post_buffer_wall and not self.jumping and not self.wall_jumping and self.post_buffer != 4:
            if self.xspeed * self.wall_normal < 0:
                self.xspeed = 0
            if self.wall_sliding and self.hor_input * self.wall_normal == -1:
                self.xspeed += 2/3 * self.wall_normal
                self.xpos += 2/3 * self.wall_normal
                self.yspeed = -1
                self.ypos -= 1
            else:
                self.xspeed += self.wall_normal
                self.xpos += self.wall_normal
                self.yspeed = min(self.yspeed, 0)
                self.yspeed -= 1.4
                self.ypos -= 1.4
            self.wall_jumping = True
            self.gravity_held_time = 1
            self.pre_buffer = 0
            self.post_buffer_wall = 0
            self.walled = False
            self.wall_sliding = 0

    def post_collision(self):
        """Perform all physics operations after the collision phase"""
        #Add player generated horizontal acceleration, if any. Make sure the x speed does not exceed max x speed.
        xspeed_pc = self.xspeed
        self.xspeed += self.hor_input * (ground_accel if self.grounded else air_accel)
        if abs(self.xspeed) > max_xspeed:
            self.xspeed = xspeed_pc

        #Check if walled
        neighbour_cells = self.neighbour_cells(self.radius + 0.1)
        for cell in neighbour_cells:
            for segment in segment_dic[cell]:
                is_walled = segment.is_wall_intersecting(self)
                if is_walled:
                    self.walled = True
        
            #Update all variables related to jump buffers
        if self.pre_buffer:
            self.pre_buffer -= 1
        if self.post_buffer:
            self.post_buffer -= 1
        if self.post_buffer_wall:
            self.post_buffer_wall -= 1
        if self.grounded:
            self.post_buffer = 5
            self.jumping = 0
            self.gravity_held_time = 0
        if self.walled:
            self.post_buffer_wall = 5
        
        #Perform jump/walljump if applicable
        if self.grounded:
            self.ground_jump()
        self.wall_jump()
        if not self.grounded:
            self.ground_jump()

        #Check if ground/wall sliding
        if self.hor_input == 0 or self.hor_input * self.xspeed < (-0.1 if self.ground_normal == (0, -1) else 0):
            self.ground_sliding += 1
        else:
            self.ground_sliding = 0
        if self.walled and self.yspeed > 0 and self.post_buffer != 4:
            if self.wall_sliding:
                if self.hor_input * self.wall_normal <= 0:
                    self.wall_sliding += 1
                else:
                    self.wall_sliding = 0
            else:
                if self.hor_input * self.wall_normal == -1:
                    self.wall_sliding = 1
        else:
            self.wall_sliding = 0

        #Apply ground/wall friction if applicable
        if self.grounded and self.ground_sliding > 1:
            if self.ground_normal == (0, -1) or self.yspeed > 0:
                self.xspeed *= friction_ground
            else:
            #This is the worst friction formula ever concieved
                speed_scalar = math.sqrt(self.xspeed**2 + self.yspeed**2)
                fric_force = abs(self.xspeed * (1-friction_ground) * self.ground_normal[1])
                fric_force2 = speed_scalar - fric_force * self.ground_normal[1]**2
                self.xspeed = self.xspeed / speed_scalar * fric_force2
                self.yspeed = self.yspeed / speed_scalar * fric_force2
        if self.wall_sliding > 1:
            self.yspeed *= friction_wall

        #If the ninja is in the state of jumping and holding the jump key, lower his applied gravity. Ignore held jump after 46 frames
        self.applied_gravity = (gravity_held if 1 <= self.gravity_held_time <= 46 else gravity)
        if not self.jump_input:
            self.jumping = False
            self.wall_jumping = False  

class GridSegmentLinear:
    """Contains all the linear segments of tiles that the ninja can interract with"""
    def __init__(self, p1, p2):
        """Initiate an instance of a linear segment of a tile. 
        Each segment is defined by the coordinates of its two end points.
        """
        self.x1 = p1[0]
        self.y1 = p1[1]
        self.x2 = p2[0]
        self.y2 = p2[1]

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
    
    def is_wall_intersecting(self, ninja):
        """Return True only if the segment is a wall that is intersecting the ninja with an increased radius of 10.1
        Also store the wall normal into the ninja's wall_normal variable"""
        if self.x1 == self.x2:
            if -(ninja.radius + 0.1) < ninja.xpos-self.x1 < 0 and self.y1 <= ninja.ypos <= self.y2:
                ninja.wall_normal = -1
                return True
            if 0 < ninja.xpos-self.x1 < (ninja.radius + 0.1) and self.y1 <= ninja.ypos <= self.y2:
                ninja.wall_normal = 1
                return True
        return False
    
class Entity:
    """Class that all entity types (gold, bounce blocks, thwumps, etc.) inherit from."""
    def __init__(self, type, xcoord, ycoord, orientation=0, mode=0):
        """Inititate a member from map data"""
        self.type = type
        self.xpos = xcoord*6
        self.ypos = ycoord*6
        self.orientation = orientation
        self.mode = mode
        self.active = True
        self.is_logical_collidable = False
        self.is_physical_collidable = False
        self.is_movable = False
        self.is_thinkable = False
        self.cell = (math.floor(self.xpos / 24), math.floor(self.ypos / 24))
        entity_dic[self.cell].append(self)
        entity_list.append(self)

    def is_colliding_circle(self, ninja):
        """Returns True if the ninja is colliding with the entity. That is, if the distance
        between the center of the ninja and the center of the entity is inferior to the lenth of the
        entity's radius plus the ninja's radius.
        """
        dx = self.xpos - ninja.xpos
        dy = self.ypos - ninja.ypos
        dist = math.sqrt(dx**2 + dy**2)
        return dist < self.radius + ninja.radius
    
    def grid_move(self):
        """As the entity is moving, if its center goes from one grid cell to another,
        remove it from the previous cell and insert it into the new cell.
        """
        entity_dic[self.cell].remove(self)
        self.cell = (math.floor(self.xpos / 24), math.floor(self.ypos / 24))
        entity_dic[self.cell].append(self)

class EntityGold(Entity):
    def __init__(self, type, xcoord, ycoord):
        super().__init__(type, xcoord, ycoord)
        self.is_logical_collidable = True
        self.radius = 6
        self.collected = False
        
    def logical_collision(self, ninja):
        """If the ninja is colliding with the piece of gold, flag it as being collected."""
        if self.is_colliding_circle(ninja):
            self.collected = True
            self.active = False

class EntityExit(Entity):
    def __init__(self, type, xcoord, ycoord):
        super().__init__(type, xcoord, ycoord)
        self.is_logical_collidable = True
        self.radius = 12
        self.open = False
        self.ninja_exit = []

    def logical_collision(self, ninja):
        """If the ninja is colliding with the open door, store the frame at which the collision happened"""
        if self.open:
            if self.is_colliding_circle(ninja):
                self.ninja_exit.append(frame)
                self.active = False

class EntityExitSwitch(Entity):
    def __init__(self, type, xcoord, ycoord, parent):
        super().__init__(type, xcoord, ycoord)
        self.is_logical_collidable = True
        self.radius = 6
        self.collected = False
        self.parent = parent

    def logical_collision(self, ninja):
        """If the ninja is colliding with the switch, flag it as being collected, and open its associated door."""
        if self.is_colliding_circle(ninja):
            self.collected = True
            self.active = False
            self.parent.open = True

class EntityBounceBlock(Entity):
    def __init__(self, type, xcoord, ycoord):
        super().__init__(type, xcoord, ycoord)
        self.is_physical_collidable = True
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
        
    def move(self):
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

    def physical_collision(self, ninja):
        depen = collision_square_vs_point((self.xpos, self.ypos), (ninja.xpos, ninja.ypos), self.semiside + ninja.radius)
        depen_x = depen[0]
        depen_y = depen[1]
        depen_len = abs(depen_x) + abs(depen_y)
        if depen_len > 0:
            ninja.xpos += depen_x * self.strength
            ninja.ypos += depen_y * self.strength
            ninja.xspeed += depen_x * self.strength
            ninja.yspeed += depen_y * self.strength
            if depen_y == 0:
                ninja.walled = True
                ninja.wall_normal = -1 if depen_x < 0 else 1
            if depen_y < 0:
                ninja.grounded = True
                ninja.ground_normal = (0, -1)
            self.xpos -= depen_x * (1-self.strength)
            self.ypos -= depen_y * (1-self.strength)
            self.xspeed -= depen_x * (1-self.strength)
            self.yspeed -= depen_y * (1-self.strength)
            self.is_immobile = False

def point_collision(p, a, b):
    """handles collision between the ninja and a specific point"""
    dx = p.xpos - a
    dy = p.ypos - b
    dist = math.sqrt(dx**2 + dy**2)
    if dist == 0:
        return
    xpos_new = a + p.radius*dx/dist
    ypos_new = b + p.radius*dy/dist
    p.xpos = xpos_new
    p.ypos = ypos_new
    dot_prod = p.xspeed * dx + p.yspeed * dy
    if (p.xspeed*dy - p.yspeed*dx) * (-dx) < 0 and dy < 0 and p.xspeed * p.hor_input > 0 and not (p.pre_buffer and not p.jumping): #if you're running uphill, you gain a bonus x speed boost
        if p.xspeed > 0:
            xspeed_boost = 1/30
        if p.xspeed < 0:
            xspeed_boost = -1/30
    else:
        xspeed_boost = 0
    if dot_prod < 0: #check if you're moving towards the corner.
        p.xspeed += xspeed_boost
        xspeed_new = (p.xspeed*dy - p.yspeed*dx) / dist**2 * dy
        yspeed_new = (p.xspeed*dy - p.yspeed*dx) / dist**2 * (-dx)
        p.xspeed = xspeed_new	
        p.yspeed = yspeed_new
    else:
        xspeed_new = xspeed_boost*dy / dist**2 * dy
        yspeed_new = xspeed_boost*dy / dist**2 * (-dx)
        p.xspeed += xspeed_new	
        p.yspeed += yspeed_new
    if not p.grounded:
        p.grounded = (dy < -0.0000001)
    if abs(dy) > 0.0000001:
        p.ground_normal = (dx/dist, dy/dist)

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
            entity.move()

    #Make all thinkable entities think.
    for entity in entity_list:
        if entity.is_thinkable and entity.active:
            entity.think()
            
    #Do pre collision calculations.
    p.pre_collision()

    #Handle PHYSICAL collisions with entities.
    neighbour_cells = p.object_neighbour_cells()
    for cell in neighbour_cells:
        for entity in entity_dic[cell]:
            if entity.is_physical_collidable and entity.active:
                entity.physical_collision(p)

    #Handle collisions with tile segments.
    for i in range(32):
        neighbour_cells = p.neighbour_cells(p.radius)
        biggest_penetration = 0 #What I did to your mom xd
        for cell in neighbour_cells:
            for segment in segment_dic[cell]:
                cloesest_point, penetration = segment.collision_check(p)
                if penetration > biggest_penetration:
                    biggest_penetration = penetration
                    closest_point_x = cloesest_point[0]
                    closest_point_y = cloesest_point[1]
        if biggest_penetration == 0:
            break
        point_collision(p, closest_point_x, closest_point_y)

    #Handle LOGICAL collisions with entities.
    neighbour_cells = p.object_neighbour_cells()
    for cell in neighbour_cells:
        for entity in entity_dic[cell]:
            if entity.is_logical_collidable and entity.active:
                entity.logical_collision(p)

    #Do post collision calculations.
    p.post_collision()

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
        if type == 2:
            EntityGold(type, xcoord, ycoord)
        if type == 3:
            parent = EntityExit(type, xcoord, ycoord)
            child_xcoord = mdata[index + 5* exit_door_count + 1]
            child_ycoord = mdata[index + 5* exit_door_count + 2]
            EntityExitSwitch(4, child_xcoord, child_ycoord, parent)
        if type == 17:
            EntityBounceBlock(type, xcoord, ycoord)
        index += 5
        if index >= len(mdata):
            break

    #Execute the main physics function once per frame
    for frame in range(1, inp_len+1):
        tick(p1, frame)

    xposlog.append(p1.xposlog)
    yposlog.append(p1.yposlog)

    if tool_mode == "splits":
        gold_amount = mdata[1154]
        gold_collected = 0
        for entity in entity_list:
            if entity.type == 2:
                if entity.collected:
                    gold_collected += 1
        goldlog.append((gold_collected, gold_amount))
        frameslog.append(inp_len)

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

    if not outte_mode:
        print(p1.speedlog)
        print(p1.poslog)
        print(valid_replay)

#Plot the route. Only ran in manual mode.
if tool_mode == "trace" and outte_mode == False:
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

