import matplotlib.pyplot as mpl
import matplotlib.collections as mc
import math
import os.path
import zlib
from itertools import product


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
        self.state = 0
        self.radius = 10
        self.hor_input = 0
        self.jump_input = 0
        self.jump_input_old = 0
        self.airborn = True
        self.walled = False
        self.jump_duration = 0
        self.jump_buffer = -1
        self.floor_buffer = -1
        self.wall_buffer = -1
        self.launch_pad_buffer = -1
        self.poslog = [(0, xspawn, yspawn)]
        self.xposlog = [xspawn]
        self.yposlog = [yspawn]
        self.speedlog = [(0,0,0)]
    
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
        entities = gather_neighbour_cells_content(self.xpos, self.ypos)
        for entity in entities:
            if entity.is_physical_collidable and entity.active:
                depen = entity.physical_collision(self)
                if depen:
                    depen_x = depen[0]
                    depen_y = depen[1]
                    depen_len = math.sqrt(depen_x**2 + depen_y**2)
                    self.xpos += depen_x
                    self.ypos += depen_y
                    if entity.type in (17, 20, 28):
                        self.xspeed += depen_x
                        self.yspeed += depen_y
                    if entity.type == 11:
                        if depen_len:
                            xspeed_new = (self.xspeed*depen_y - self.yspeed*depen_x) / depen_len**2 * depen_y
                            yspeed_new = (self.xspeed*depen_y - self.yspeed*depen_x) / depen_len**2 * (-depen_x)
                            self.xspeed = xspeed_new
                            self.yspeed = yspeed_new
                    if depen_y < 0:
                        self.floor_count += 1
                        self.floor_normal_x += depen_x / depen_len
                        self.floor_normal_y += depen_y / depen_len

    def collide_vs_tiles(self):
        dx = self.xpos - self.xpos_old
        dy = self.ypos - self.ypos_old
        time = sweep_circle_vs_tiles(self.xpos_old, self.ypos_old, dx, dy, self.radius * 0.5)
        self.xpos = self.xpos_old + time * dx
        self.ypos = self.ypos_old + time * dy
        for point in range(32):
            closest_point = get_single_closest_point(self.xpos, self.ypos, self.radius)
            if not closest_point:
                break
            a = closest_point[0]
            b = closest_point[1]
            dx = self.xpos - a
            dy = self.ypos - b
            if abs(dx) <= 0.0000001: #This is to prevent corner cases. Not in the original code
                dx = 0
            if self.xpos in (50.51197510492316, 49.23232124849253) : #This is to artificially create corner cases at certain common exact spots. lol
                dx = -2**-47
            if self.xpos == 49.153536108584795 :
                dx = 2**-47
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
                self.floor_normal_x += dx/dist
                self.floor_normal_y += dy/dist
    
    def post_collision(self):
        wall_normal = 0

        #Perform LOGICAL collisions between the ninja and nearby entities.
        #Also check if the ninja can interact with the walls of entities when applicable.
        entities = gather_neighbour_cells_content(self.xpos, self.ypos)
        for entity in entities:
            if entity.is_logical_collidable and entity.active:
                collision_result = entity.logical_collision(self)
                if collision_result:
                    if entity.type == 10: #If collision with launch pad
                        xboost = collision_result[0] * 2/3
                        yboost = collision_result[1] * 2/3
                        self.xpos += xboost
                        self.ypos += yboost
                        self.xspeed = xboost
                        self.yspeed = yboost
                        self.floor_count = 0
                        self.floor_buffer = -1
                        
                        boost_scalar = math.sqrt(xboost**2 + yboost**2)
                        self.xlp_boost_normalized = xboost/boost_scalar
                        self.ylp_boost_normalized = yboost/boost_scalar
                        self.launch_pad_buffer = 0
                        if self.state == 3:
                            self.applied_gravity = gravity
                        self.state = 4
                    else: #If touched wall of bounce block, oneway, thwump or shwump
                        wall_normal += collision_result                  

        #Check if the ninja can interact with nearby walls.
        rad = self.radius + 0.1
        neighbour_cells = gather_cells_from_region(self.xpos-rad, self.ypos-rad, self.xpos+rad, self.ypos+rad)
        for cell in neighbour_cells:
            for segment in segment_dic[cell]:
                if segment.active and segment.type == "linear":
                    collision_result = segment.wall_intersecting(self)
                    if collision_result:
                        wall_normal += collision_result

        self.airborn = True
        self.walled = False
        if wall_normal:
            self.walled = True
            self.wall_normal = wall_normal/abs(wall_normal)

        #Calculate the combined floor normalized normal vector if the ninja has touched any floor.
        if self.floor_count > 0:
            self.airborn = False
            floor_scalar = math.sqrt(self.floor_normal_x**2 + self.floor_normal_y**2)
            if floor_scalar == 0:
                self.floor_normalized_x = 0
                self.floor_normalized_y = -1
            else:
                self.floor_normalized_x = self.floor_normal_x/floor_scalar
                self.floor_normalized_y = self.floor_normal_y/floor_scalar

    def floor_jump(self):
        self.jump_buffer = -1
        self.floor_buffer = -1
        self.launch_pad_buffer = -1
        self.state = 3
        self.applied_gravity = gravity_held
        if self.floor_normalized_x == 0:
            jx = 0
            jy = -2
        else:
            dx = self.floor_normalized_x
            dy = self.floor_normalized_y
            if self.xspeed * dx >= 0:
                if self.xspeed * self.hor_input >= 0:
                    jx = 2/3 * dx
                    jy = 2 * dy
                else:
                    jx = 0
                    jy = -1.4
            else:
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
        self.jump_buffer = -1
        self.wall_buffer = -1
        self.launch_pad_buffer = -1
        self.jump_duration = 0

    def lp_jump(self):
        self.floor_buffer = -1
        self.wall_buffer = -1
        self.jump_buffer = -1
        self.launch_pad_buffer = -1
        boost_scalar = 2 * abs(self.xlp_boost_normalized) + 2
        if boost_scalar == 2:
            boost_scalar = 1.7 #This was really needed. Thanks Metanet
        self.xspeed += self.xlp_boost_normalized * boost_scalar * 2/3
        self.yspeed += self.ylp_boost_normalized * boost_scalar * 2/3
        
    def think(self):
        #Logic to determine if you're starting a new jump.
        if not self.jump_input:
            new_jump_check = False
        else:
            new_jump_check = self.jump_input_old == 0
        self.jump_input_old = self.jump_input

        #Determine if within buffer ranges. If so, increment buffers.
        if -1 < self.launch_pad_buffer < 3:
            self.launch_pad_buffer += 1
        else:
            self.launch_pad_buffer = -1
        in_lp_buffer = -1 < self.launch_pad_buffer < 4
        if -1 < self.jump_buffer < 5:
            self.jump_buffer += 1
        else:
            self.jump_buffer = -1
        in_jump_buffer = -1 < self.jump_buffer < 5
        if -1 < self.wall_buffer < 5:
            self.wall_buffer += 1
        else:
            self.wall_buffer = -1
        in_wall_buffer = -1 < self.wall_buffer < 5
        if -1 < self.floor_buffer < 5:
            self.floor_buffer += 1
        else:
            self.floor_buffer = -1
        in_floor_buffer = -1 < self.floor_buffer < 5

        #Initiate jump buffer if beginning a new jump and airborn.
        if new_jump_check and self.airborn:
            self.jump_buffer = 0
        #Initiate wall buffer if touched a wall this frame.
        if self.walled:
            self.wall_buffer = 0
        #Initiate floor buffer if touched a floor this frame.
        if not self.airborn:
            self.floor_buffer = 0

        #This block deals with the case where the ninja is touching a floor.
        if not self.airborn: 
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
            if not in_jump_buffer and not new_jump_check: #if not jumping
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
            #if you're jumping
            self.floor_jump()
            return

        #This block deals with the case where the ninja didn't touch a floor
        else:
            xspeed_new = self.xspeed + air_accel * self.hor_input
            if abs(xspeed_new) < max_xspeed:
                self.xspeed = xspeed_new
            if self.state < 3:
                self.state = 4
                return
            if self.state == 3:
                self.jump_duration += 1
                if not self.jump_input or self.jump_duration > max_jump_duration:
                    self.applied_gravity = gravity
                    self.state = 4
                    return
            if in_jump_buffer or new_jump_check: #if able to perfrom jump
                if self.walled or in_wall_buffer:
                    self.wall_jump()
                    return
                if in_floor_buffer:
                    self.floor_jump()
                    return
                if in_lp_buffer and new_jump_check:
                    self.lp_jump()
                    return
            if not self.walled:
                if self.state == 5:
                    self.state = 4
            else:
                if self.state == 5:
                    if self.hor_input * self.wall_normal <= 0:
                        self.yspeed *= friction_wall
                    else:
                        self.state = 4
                else:
                    if self.yspeed > 0 and self.hor_input * self.wall_normal < 0:
                        if self.state == 3:
                            self.applied_gravity = gravity
                        self.state = 5

class GridSegmentLinear:
    """Contains all the linear segments of tiles and doors that the ninja can interract with"""
    def __init__(self, p1, p2):
        """Initiate an instance of a linear segment of a tile. 
        Each segment is defined by the coordinates of its two end points.
        """
        self.x1, self.y1 = p1
        self.x2, self.y2 = p2
        self.active = True
        self.type = "linear"

    def collision_check(self, xpos, ypos, radius):
        """Check if the ninja is interesecting with the segment.
        If so, calculate the penetration length and the closest point on the segment from the center of the ninja.
        """
        px = self.x2 - self.x1
        py = self.y2 - self.y1
        seg_lensq = px**2 + py**2
        u = ((xpos-self.x1)*px + (ypos-self.y1)*py)/seg_lensq
        u = max(u, 0)
        u = min(u, 1)
        x = self.x1 + u*px
        y = self.y1 + u*py
        dist = math.sqrt((xpos-x)**2 + (ypos-y)**2)
        penetration = radius - dist if dist < 9.9999999 else 0
        return (x, y), penetration
    
    def intersect_with_ray(self, xpos, ypos, dx, dy, radius):
        time1 = get_time_of_intersection_circle_vs_circle(xpos, ypos, dx, dy, self.x1, self.y1, radius)
        time2 = get_time_of_intersection_circle_vs_circle(xpos, ypos, dx, dy, self.x2, self.y2, radius)
        time3 = get_time_of_intersection_circle_vs_lineseg(xpos, ypos, dx, dy, self.x1, self.y1, self.x2, self.y2, radius)
        return min(time1, time2, time3)
    
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

    def collision_check(self, xpos, ypos, radius):
        """Check if the ninja is interesecting with the segment.
        If so, calculate the penetration length and the closest point on the segment from the center of the ninja.
        """
        dx = xpos - self.xpos
        dy = ypos - self.ypos
        if dx * self.hor > 0 and dy * self.ver > 0:
            dist = math.sqrt(dx**2 + dy**2)
            x = self.xpos + self.radius * dx / dist
            y = self.ypos + self.radius * dy / dist
            if self.convex:
                penetration = radius + self.radius - dist
            else:
                penetration = dist + radius - self.radius
        else:
            if dx * self.hor <= 0 and dy * self.ver > 0:
                x = self.xpos
                y = self.ypos + self.radius * self.ver
            elif dx * self.hor > 0 and dy * self.ver <= 0:
                x = self.xpos + self.radius * self.hor
                y = self.ypos
            else:
                return (self.xpos, self.ypos), 0
            penetration = math.sqrt((xpos - x)**2 + (ypos - y)**2)
        if penetration < 0.0000001 or penetration > 10 :
            penetration = 0
        return (x, y), penetration
    
    def intersect_with_ray(self, xpos, ypos, dx, dy, radius):
        pass

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
        if self.type != 3:
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
        cell_new = (math.floor(self.xpos / 24), math.floor(self.ypos / 24))
        if cell_new != self.cell:
            entity_dic[self.cell].remove(self)
            self.cell = cell_new
            entity_dic[self.cell].append(self)

class EntityGold(Entity):
    def __init__(self, type, xcoord, ycoord):
        super().__init__(type, xcoord, ycoord)
        self.is_logical_collidable = True
        self.radius = 6
        self.collected = False
        
    def logical_collision(self, ninja):
        """If the ninja is colliding with the piece of gold, flag it as being collected."""
        if self.is_colliding_circle(ninja, ninja.radius):
            self.collected = frame
            self.active = False

class EntityExit(Entity):
    def __init__(self, type, xcoord, ycoord):
        super().__init__(type, xcoord, ycoord)
        self.is_logical_collidable = True
        self.radius = 12
        self.ninja_exit = []

    def logical_collision(self, ninja):
        """If the ninja is colliding with the open door, store the frame at which the collision happened"""
        if self.is_colliding_circle(ninja, ninja.radius):
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
        if self.is_colliding_circle(ninja, ninja.radius):
            self.collected = True
            self.active = False
            entity_dic[self.parent.cell].append(self.parent) #Add door to the entity grid so the ninja can touch it

class EntityDoorBase(Entity):
    def __init__(self, type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord):
        super().__init__(type, xcoord, ycoord)
        self.is_logical_collidable = True
        self.closed = True
        self.sw_xpos = 6 * sw_xcoord
        self.sw_ypos = 6 * sw_ycoord
        self.grid_segment_coords = []
        self.is_vertical = orientation in (0, 4)
        if self.is_vertical:
            self.segment = GridSegmentLinear((self.xpos, self.ypos-12), (self.xpos, self.ypos+12))
            self.grid_segment_coords.append((math.ceil(self.xpos/12)-1, math.ceil(self.ypos/12)-1))
            self.grid_segment_coords.append((math.ceil(self.xpos/12)-1, math.ceil(self.ypos/12)))
        else:
            self.segment = GridSegmentLinear((self.xpos-12, self.ypos), (self.xpos+12, self.ypos))
            self.grid_segment_coords.append((math.ceil(self.xpos/12)-1, math.ceil(self.ypos/12)-1))
            self.grid_segment_coords.append((math.ceil(self.xpos/12), math.ceil(self.ypos/12)-1))
        segment_dic[self.cell].append(self.segment)
        self.xpos = self.sw_xpos
        self.ypos = self.sw_ypos
        self.grid_move()

    def change_state(self, closed):
        #Change the state of the door from closed to open or from open to closed.
        self.closed = closed
        self.segment.active = closed
        for coord in self.grid_segment_coords:
            if self.is_vertical:
                ver_grid_edge_dic[coord] += 1 if closed else -1
            else:
                hor_grid_edge_dic[coord] += 1 if closed else -1

class EntityDoorRegular(EntityDoorBase):
    def __init__(self, type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord):
        super().__init__(type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord)
        self.is_thinkable = True
        self.radius = 10
        self.open_timer = 0

    def think(self, ninja):
        #If the door has been opened for more than 5 frames without being touched by the ninja, close it.
        if not self.closed:
            self.open_timer += 1
            if self.open_timer > 5:
                self.change_state(closed = True)

    def logical_collision(self, ninja):
        #If the ninja touches the activation region of the door, open it.
        if self.is_colliding_circle(ninja, ninja.radius):
            self.change_state(closed = False)
            self.open_timer = 0

class EntityDoorLocked(EntityDoorBase):
    def __init__(self, type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord):
        super().__init__(type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord)
        self.radius = 5

    def logical_collision(self, ninja):
        #If the ninja collects the associated open switch, open the door.
        if self.is_colliding_circle(ninja, ninja.radius):
            self.change_state(closed = False)
            self.active = False

class EntityDoorTrap(EntityDoorBase):
    def __init__(self, type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord):
        super().__init__(type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord)
        self.radius = 5
        self.closed = False
        self.segment.active = False

    def logical_collision(self, ninja):
        #If the ninja collects the associated close switch, close the door.
        if self.is_colliding_circle(ninja, ninja.radius):
            self.change_state(closed = True)
            self.active = False

class EntityLaunchPad(Entity):
    def __init__(self, type, xcoord, ycoord, orientation):
        super().__init__(type, xcoord, ycoord)
        self.is_logical_collidable = True
        normal = map_orientation_to_vector(orientation)
        self.normal_x = normal[0]
        self.normal_y = normal[1]
        self.radius = 6
        self.boost = 36/7

    def logical_collision(self, ninja):
        if self.is_colliding_circle(ninja, ninja.radius):
            if (self.xpos - (ninja.xpos - ninja.radius*self.normal_x))*self.normal_x + (self.ypos - (ninja.ypos - ninja.radius*self.normal_y))*self.normal_y >= -0.1:
                yboost_scale = 1
                if self.normal_y < 0:
                    yboost_scale = 1 - self.normal_y
                xboost = self.normal_x * self.boost
                yboost = self.normal_y * self.boost * yboost_scale
                return (xboost, yboost)

class EntityOneWayPlatform(Entity):
    def __init__(self, type, xcoord, ycoord, orientation):
        super().__init__(type, xcoord, ycoord)
        self.is_logical_collidable = True
        self.is_physical_collidable = True
        normal = map_orientation_to_vector(orientation)
        self.normal_x = normal[0]
        self.normal_y = normal[1]
        self.semiside = 12

    def calculate_depenetration(self, ninja):
        dx = ninja.xpos - self.xpos
        dy = ninja.ypos - self.ypos
        lateral_dist = dy * self.normal_x - dx * self.normal_y
        direction = (ninja.yspeed * self.normal_x - ninja.xspeed * self.normal_y) * lateral_dist
        radius_scalar = 0.91 if direction < 0 else 0.51
        if abs(lateral_dist) < radius_scalar * ninja.radius + self.semiside:
            normal_dist = dx * self.normal_x + dy * self.normal_y
            if 0 < normal_dist <= ninja.radius:
                normal_proj = ninja.xspeed * self.normal_x + ninja.yspeed * self.normal_y
                if normal_proj <= 0:
                    dx_old = ninja.xpos_old - self.xpos
                    dy_old = ninja.ypos_old - self.ypos
                    normal_dist_old = dx_old * self.normal_x + dy_old * self.normal_y
                    if ninja.radius - normal_dist_old <= 1.1:
                        depen_x = self.normal_x * (ninja.radius - normal_dist)
                        depen_y = self.normal_y * (ninja.radius - normal_dist)
                        return (depen_x, depen_y)

    def physical_collision(self, ninja):
        return self.calculate_depenetration(ninja)

    def logical_collision(self, ninja):
        collision_result = self.calculate_depenetration(ninja)
        if collision_result:
            if abs(self.normal_x) == 1:
                return self.normal_x
        
class EntityBounceBlock(Entity):
    def __init__(self, type, xcoord, ycoord):
        super().__init__(type, xcoord, ycoord)
        self.is_physical_collidable = True
        self.is_logical_collidable = True
        self.is_movable = True
        self.is_thinkable = False
        self.xspeed = 0
        self.yspeed = 0
        self.xorigin = self.xpos
        self.yorigin = self.ypos
        self.semiside = 9
        self.stiffness = 0.02222222222222222
        self.dampening = 0.98
        self.strength = 0.2
        self.log = [(self.xpos, self.ypos)]
        
    def move(self, ninja):
        """Update the position and speed of the bounce block by applying the spring force and dampening."""
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

    def physical_collision(self, ninja):
        #Collide with the ninja. 
        depen = collision_square_vs_point((self.xpos, self.ypos), (ninja.xpos, ninja.ypos), self.semiside, ninja.radius)
        depen_x = depen[0]
        depen_y = depen[1]
        depen_len = abs(depen_x) + abs(depen_y)
        if depen_len > 0:
            self.xpos -= depen_x * (1-self.strength)
            self.ypos -= depen_y * (1-self.strength)
            self.xspeed -= depen_x * (1-self.strength)
            self.yspeed -= depen_y * (1-self.strength)
            return (depen_x * self.strength, depen_y * self.strength)
        
    def logical_collision(self, ninja):
        #Check if the ninja can interact with the wall of the bounce block
        depen = collision_square_vs_point((self.xpos, self.ypos), (ninja.xpos, ninja.ypos), self.semiside, ninja.radius + 0.1)
        depen_x = depen[0]
        if depen_x:
            return depen_x/abs(depen_x)
        
class EntityThwump(Entity):
    def __init__(self, type, xcoord, ycoord, orientation):
        super().__init__(type, xcoord, ycoord)
        self.is_movable = True
        self.is_thinkable = True
        self.is_logical_collidable = True
        self.is_physical_collidable = True
        self.is_horizontal = orientation in (0, 4)
        self.direction = 1 if orientation in (0, 2) else -1
        self.xorigin = self.xpos
        self.yorigin = self.ypos
        self.semiside = 9
        self.forward_speed = 20/7
        self.backward_speed = 8/7
        self.state = 0 #0:immobile, 1:forward, -1:backward

    def move(self, ninja):
        if self.state:
            speed = self.forward_speed if self.state == 1 else self.backward_speed
            speed_dir = self.direction * self.state
            if not self.is_horizontal:
                ypos_new = self.ypos + speed * speed_dir
                if self.state == -1 and (ypos_new - self.yorigin) * (self.ypos - self.yorigin) < 0: #If the thwump as retreated past its starting point.
                    self.ypos = self.yorigin
                    self.state = 0
                    return
                cell_y = math.floor((self.ypos + speed_dir * 11) / 12)
                cell_y_new = math.floor((ypos_new + speed_dir * 11) / 12)
                if cell_y != cell_y_new:
                    cell_x1 = math.floor((self.xpos - 11) / 12)
                    cell_x2 = math.floor((self.xpos + 11) / 12)
                    if not is_empty_row(cell_x1, cell_x2, cell_y, speed_dir):
                        self.state = -1
                        return
                self.ypos = ypos_new
            else:
                xpos_new = self.xpos + speed * speed_dir
                if self.state == -1 and (xpos_new - self.xorigin) * (self.xpos - self.xorigin) < 0: #If the thwump as retreated past its starting point.
                    self.xpos = self.xorigin
                    self.state = 0
                    return
                cell_x = math.floor((self.xpos + speed_dir * 11) / 12)
                cell_x_new = math.floor((xpos_new + speed_dir * 11) / 12)
                if cell_x != cell_x_new:
                    cell_y1 = math.floor((self.ypos - 11) / 12)
                    cell_y2 = math.floor((self.ypos + 11) / 12)
                    if not is_empty_column(cell_x, cell_y1, cell_y2, speed_dir):
                        self.state = -1
                        return
                self.xpos = xpos_new
            self.grid_move()

    def think(self, ninja):
        if not self.state:
            activation_range = 2 * (self.semiside + ninja.radius)
            if not self.is_horizontal:
                if abs(self.xpos - ninja.xpos) < activation_range: #If the ninja is in the activation range
                    ninja_ycell = math.floor(ninja.ypos / 12)
                    thwump_ycell = math.floor((self.ypos - self.direction * 11) / 12)
                    thwump_xcell1 = math.floor((self.xpos - 11) / 12)
                    thwump_xcell2 = math.floor((self.xpos + 11) / 12)
                    dy = ninja_ycell - thwump_ycell
                    if dy * self.direction < 0:
                        return
                    while dy * self.direction >= 0:
                        if dy == 0:
                            self.state = 1
                            return
                        if not is_empty_row(thwump_xcell1, thwump_xcell2, thwump_ycell, self.direction):
                            return
                        thwump_ycell += self.direction
                        dy = ninja_ycell - thwump_ycell
            else:
                if abs(self.ypos - ninja.ypos) < activation_range: #If the ninja is in the activation range
                    ninja_xcell = math.floor(ninja.xpos / 12)
                    thwump_xcell = math.floor((self.xpos - self.direction * 11) / 12)
                    thwump_ycell1 = math.floor((self.ypos - 11) / 12)
                    thwump_ycell2 = math.floor((self.ypos + 11) / 12)
                    dx = ninja_xcell - thwump_xcell
                    if dx * self.direction < 0:
                        return
                    while dx * self.direction >= 0:
                        if dx == 0:
                            self.state = 1
                            return
                        if not is_empty_column(thwump_xcell, thwump_ycell1, thwump_ycell2, self.direction):
                            return
                        thwump_xcell += self.direction
                        dx = ninja_xcell - thwump_xcell

    def physical_collision(self, ninja):
        depen = collision_square_vs_point((self.xpos, self.ypos), (ninja.xpos, ninja.ypos), self.semiside, ninja.radius)
        if depen != (0, 0):
            return depen
    
    def logical_collision(self, ninja):
        depen = collision_square_vs_point((self.xpos, self.ypos), (ninja.xpos, ninja.ypos), self.semiside, ninja.radius + 0.1)
        depen_x = depen[0]
        if depen_x:
            return depen_x/abs(depen_x)

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

class EntityShoveThwump(Entity):
    def __init__(self, type, xcoord, ycoord):
        super().__init__(type, xcoord, ycoord)
        self.is_thinkable = True
        self.is_logical_collidable = True
        self.is_physical_collidable = True
        self.xorigin = self.xpos
        self.yorigin = self.ypos
        self.semiside = 12
        self.xdir = 0
        self.ydir = 0
        self.state = 0 #0:immobile, 1:activated, 2:launching, 3:retreating
        self.activated = False

    def think(self, ninja):
        if self.state == 1: 
            if self.activated:
                self.activated = False
                return
            self.state = 2
        if self.state == 3:
            origin_dist = abs(self.xpos - self.xorigin) + abs(self.ypos - self.yorigin)
            if origin_dist >= 1:
                self.move_if_possible(self.xdir, self.ydir, 1)
            else:
                self.xpos = self.xorigin
                self.ypos = self.yorigin
                self.state = 0
        elif self.state == 2:
            self.move_if_possible(-self.xdir, -self.ydir, 4)

    def move_if_possible(self, xdir, ydir, speed):
        if self.ydir == 0:
            xpos_new = self.xpos + xdir * speed
            cell_x = math.floor(self.xpos / 12)
            cell_x_new = math.floor(xpos_new / 12)
            if cell_x != cell_x_new:
                cell_y1 = math.floor((self.ypos - 8) / 12)
                cell_y2 = math.floor((self.ypos + 8) / 12)
                if not is_empty_column(cell_x, cell_y1, cell_y2, xdir):
                    self.state = 3
                    return
            self.xpos = xpos_new
        else:
            ypos_new = self.ypos + ydir * speed
            cell_y = math.floor(self.ypos / 12)
            cell_y_new = math.floor(ypos_new / 12)
            if cell_y != cell_y_new:
                cell_x1 = math.floor((self.xpos - 8) / 12)
                cell_x2 = math.floor((self.xpos + 8) / 12)
                if not is_empty_row(cell_x1, cell_x2, cell_y, ydir):
                    self.state = 3
                    return
            self.ypos = ypos_new
        self.grid_move()
            
    def physical_collision(self, ninja):
        if self.state <= 1:
            depen = collision_square_vs_point((self.xpos, self.ypos), (ninja.xpos, ninja.ypos), self.semiside, ninja.radius)
            if depen != (0, 0):
                if self.state == 0 or self.xdir * depen[0] + self.ydir * depen[1] >= 0.01:
                    return depen

    def logical_collision(self, ninja):
        depen = collision_square_vs_point((self.xpos, self.ypos), (ninja.xpos, ninja.ypos), self.semiside, ninja.radius + 0.1)
        if depen != (0, 0) and self.state <= 1:
            if self.state == 0:
                self.activated = True
                depen_x, depen_y = depen
                depen_len = abs(depen_x) + abs(depen_y)
                self.xdir = depen_x/depen_len
                self.ydir = depen_y/depen_len
                self.state = 1
            elif self.state == 1:
                if self.xdir * depen[0] + self.ydir * depen[1] >= 0.01:
                    self.activated = True
                else:
                    return               
            if depen[0]:
                return depen[0]/abs(depen[0])

def gather_cells_from_region(x1, y1, x2, y2):
        """Return a list containing all cells that contain a rectangle bounded by 2 points"""
        cx1 = math.floor(x1/24)
        cy1 = math.floor(y1/24)
        cx2 = math.floor(x2/24)
        cy2 = math.floor(y2/24)
        return product(range(cx1, cx2 + 1), range(cy1, cy2 + 1))

def gather_neighbour_cells_content(xpos, ypos):
        """Return a list that contains all the cells that could contain objects which the ninja could interact with.
        This list contains nine cells. The one containing the center of the ninja and the eight cells around it.
        """
        cx = math.floor(xpos/24)
        cy = math.floor(ypos/24)
        cells = product(range(cx - 1, cx + 2), range(cy - 1, cy + 2))
        entity_list = []
        for cell in cells:
            entity_list += entity_dic[cell]
        return entity_list

def get_single_closest_point(xpos, ypos, radius):
    neighbour_cells = gather_cells_from_region(xpos-radius, ypos-radius, xpos+radius, ypos+radius)
    biggest_penetration = 0
    for cell in neighbour_cells:
        for segment in segment_dic[cell]:
            if segment.active:
                point, penetration = segment.collision_check(xpos, ypos, radius)
                if penetration > biggest_penetration:
                    biggest_penetration = penetration
                    closest_point = point
    if biggest_penetration > 0:
        return closest_point
    
def sweep_circle_vs_tiles(xpos_old, ypos_old, dx, dy, radius):
    xpos_new = xpos_old + dx
    ypos_new = ypos_old + dy
    width = radius + 1
    x1 = min(xpos_old, xpos_new) - width
    y1 = min(ypos_old, ypos_new) - width
    x2 = max(xpos_old, xpos_new) + width
    y2 = max(ypos_old, ypos_new) + width
    cells = gather_cells_from_region(x1, y1, x2, y2)
    shortest_time = 1
    for cell in cells:
        for segment in segment_dic[cell]:
            if segment.active and segment.type == "linear":
                time = segment.intersect_with_ray(xpos_old, ypos_old, dx, dy, radius)
                shortest_time = min(time, shortest_time)
    return shortest_time

def get_time_of_intersection_circle_vs_circle(xpos, ypos, vx, vy, a, b, radius):
    dx = xpos - a
    dy = ypos - b
    dist_sq = dx**2 + dy**2
    radius_sq = radius**2
    vel_sq = vx**2 + vy**2
    dot_prod = dx * vx + dy * vy
    if (dist_sq - radius_sq) > 0:
        if vel_sq > 0.0001 and dot_prod < 0 and dot_prod**2 >= vel_sq * (dist_sq - radius_sq):
            return (-dot_prod - math.sqrt(dot_prod**2 - vel_sq * (dist_sq - radius_sq))) / vel_sq
        return 1
    return 0

def get_time_of_intersection_circle_vs_lineseg(xpos, ypos, dx, dy, a1, b1, a2, b2, radius):
    wx = a2 - a1
    wy = b2 - b1
    seg_len = math.sqrt(wx**2 + wy**2)
    nx = wx / seg_len
    ny = wy / seg_len
    normal_proj = (xpos - a1) * ny - (ypos - b1) * nx
    hor_proj = (xpos - a1) * nx + (ypos - b1) * ny
    if abs(normal_proj) >= radius:
        dir = dx * ny - dy * nx
        if dir * normal_proj < 0:
            t = min(abs(normal_proj - radius) / abs(dir), 1)
            hor_proj2 = hor_proj + t * (dx * nx  + dy * ny)
            if 0 <= hor_proj2 <= seg_len:
                return t
    else:
        if 0 <= hor_proj <= seg_len:
            return 0
    return 1

def get_time_of_intersection_circle_vs_arc():
    pass

def collision_square_vs_point(square_pos, point_pos, semiside, radius):
    """Return the depenetration vector to depenetrate a point out of a square.
    Used to collide the ninja with square entities. (bounce blocks, thwumps, shwumps)"""
    x0 = square_pos[0]
    y0 = square_pos[1]
    x1 = point_pos[0]
    y1 = point_pos[1]
    dx = x1 - x0
    dy = y1 - y0
    penx = semiside + radius - abs(dx)
    peny = semiside + radius - abs(dy)
    if  penx > 0 and peny > 0:
        if peny <= penx:
            return (0, -peny) if dy < 0 else (0, peny)
        return (-penx, 0) if dx < 0 else (penx, 0)
    return (0, 0)

def map_orientation_to_vector(orientation):
    """Return a normalized vector pointing in the direction of the orientation.
    Orientation is a value between 0 and 7 taken from map data.
    """
    diag = math.sqrt(2) / 2
    orientation_dic = {0:(1, 0), 1:(diag, diag), 2:(0, 1), 3:(-diag, diag), 4:(-1, 0), 5:(-diag, -diag), 6:(0, -1), 7:(diag, -diag)}
    return orientation_dic[orientation]

def is_empty_row(xcoord1, xcoord2, ycoord, dir):
    """Return true if the cell has no solid horizontal edge in the specified direction."""
    xcoord3 = xcoord1 if xcoord1 == xcoord2 else xcoord1 + 1
    if dir == 1:
        return not (hor_grid_edge_dic[xcoord1, ycoord+1] or hor_grid_edge_dic[xcoord2, ycoord+1] or hor_grid_edge_dic[xcoord3, ycoord+1])
    if dir == -1:
        return not (hor_grid_edge_dic[xcoord1, ycoord] or hor_grid_edge_dic[xcoord2, ycoord] or hor_grid_edge_dic[xcoord3, ycoord])
    
def is_empty_column(xcoord, ycoord1, ycoord2, dir):
    """Return true if the cell has no solid vertical edge in the specified direction."""
    ycoord3 = ycoord1 if ycoord1 == ycoord2 else ycoord1 + 1
    if dir == 1:
        return not (ver_grid_edge_dic[xcoord+1, ycoord1] or ver_grid_edge_dic[xcoord+1, ycoord2] or ver_grid_edge_dic[xcoord+1, ycoord3])
    if dir == -1:
        return not (ver_grid_edge_dic[xcoord, ycoord1] or ver_grid_edge_dic[xcoord, ycoord2] or ver_grid_edge_dic[xcoord, ycoord3])
          
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
            entity.think(p)
 
    p.integrate() #Do preliminary speed and position updates.
    p.pre_collision() #Do pre collision calculations.
    for _ in range(4):
        p.collide_vs_objects() #Handle PHYSICAL collisions with entities.
        p.collide_vs_tiles() #Handle physical collisions with tiles.
    p.post_collision() #Do post collision calculations.
    p.think() #Make ninja think

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
    for x in range(45):
        for y in range(26):
            segment_dic[(x, y)] = []
    entity_dic = {}
    for x in range(44):
        for y in range(25):
            entity_dic[(x, y)] = []
    entity_list = []

    #Initiate dictionaries of grid edges and segments. They are all set to zero initialy. Increment by 1 whenever a grid edge or segment is spawned.
    hor_grid_edge_dic = {}
    for x in range(88):
        for y in range(51):
            hor_grid_edge_dic[(x, y)] = 0
    ver_grid_edge_dic = {}
    for x in range(89):
        for y in range(50):
            ver_grid_edge_dic[(x, y)] = 0
    hor_segment_dic = {}
    for x in range(88):
        for y in range(51):
            hor_segment_dic[(x, y)] = 0
    ver_segment_dic = {}
    for x in range(89):
        for y in range(50):
            ver_segment_dic[(x, y)] = 0
    
    tile_grid_edge_map = {0:[0,0,0,0,0,0,0,0,0,0,0,0], 1:[1,1,0,0,1,1,1,1,0,0,1,1], #Empty and full tiles
                          2:[1,1,1,1,0,0,1,0,0,0,1,0], 3:[0,1,0,0,0,1,0,0,1,1,1,1], 4:[0,0,1,1,1,1,0,1,0,0,0,1], 5:[1,0,0,0,1,0,1,1,1,1,0,0], #Half tiles
                          6:[1,1,0,1,1,0,1,1,0,1,1,0], 7:[1,1,1,0,0,1,1,0,0,1,1,1], 8:[0,1,1,0,1,1,0,1,1,0,1,1], 9:[1,0,0,1,1,1,1,1,1,0,0,1], #45 degree tiles
                          10:[1,1,0,0,1,1,1,1,0,0,1,1], 11:[1,1,0,0,1,1,1,1,0,0,1,1], 12:[1,1,0,0,1,1,1,1,0,0,1,1], 13:[1,1,0,0,1,1,1,1,0,0,1,1], #Quarter moons
                          14:[1,1,0,1,1,0,1,1,0,1,1,0], 15:[1,1,1,0,0,1,1,0,0,1,1,1], 16:[0,1,1,0,1,1,0,1,1,0,1,1], 17:[1,0,0,1,1,1,1,1,1,0,0,1], #Quarter pipes
                          18:[1,1,1,1,0,0,1,0,0,0,1,0], 19:[1,1,1,1,0,0,1,0,0,0,1,0], 20:[0,0,1,1,1,1,0,1,0,0,0,1], 21:[0,0,1,1,1,1,0,1,0,0,0,1], #Short mild slopes
                          22:[1,1,0,0,1,1,1,1,0,0,1,1], 23:[1,1,0,0,1,1,1,1,0,0,1,1], 24:[1,1,0,0,1,1,1,1,0,0,1,1], 25:[1,1,0,0,1,1,1,1,0,0,1,1], #Raised mild slopes
                          26:[1,0,0,0,1,0,1,1,1,1,0,0], 27:[0,1,0,0,0,1,0,0,1,1,1,1], 28:[0,1,0,0,0,1,0,0,1,1,1,1], 29:[1,0,0,0,1,0,1,1,1,1,0,0], #Short steep slopes
                          30:[1,1,0,0,1,1,1,1,0,0,1,1], 31:[1,1,0,0,1,1,1,1,0,0,1,1], 32:[1,1,0,0,1,1,1,1,0,0,1,1], 33:[1,1,0,0,1,1,1,1,0,0,1,1]} #Raised steep slopes
    tile_segment_map = {0:[0,0,0,0,0,0,0,0,0,0,0,0], 1:[1,1,0,0,1,1,1,1,0,0,1,1], #Empty and full tiles
                        2:[1,1,1,1,0,0,1,0,0,0,1,0], 3:[0,1,0,0,0,1,0,0,1,1,1,1], 4:[0,0,1,1,1,1,0,1,0,0,0,1], 5:[1,0,0,0,1,0,1,1,1,1,0,0], #Half tiles
                        6:[1,1,0,0,0,0,1,1,0,0,0,0], 7:[1,1,0,0,0,0,0,0,0,0,1,1], 8:[0,0,0,0,1,1,0,0,0,0,1,1], 9:[0,0,0,0,1,1,1,1,0,0,0,0], #45 degree tiles
                        10:[1,1,0,0,0,0,1,1,0,0,0,0], 11:[1,1,0,0,0,0,0,0,0,0,1,1], 12:[0,0,0,0,1,1,0,0,0,0,1,1], 13:[0,0,0,0,1,1,1,1,0,0,0,0], #Quarter moons
                        14:[1,1,0,0,0,0,1,1,0,0,0,0], 15:[1,1,0,0,0,0,0,0,0,0,1,1], 16:[0,0,0,0,1,1,0,0,0,0,1,1], 17:[0,0,0,0,1,1,1,1,0,0,0,0], #Quarter pipes
                        18:[1,1,0,0,0,0,1,0,0,0,0,0], 19:[1,1,0,0,0,0,0,0,0,0,1,0], 20:[0,0,0,0,1,1,0,0,0,0,0,1], 21:[0,0,0,0,1,1,0,1,0,0,0,0], #Short mild slopes
                        22:[1,1,0,0,0,0,1,1,0,0,1,0], 23:[1,1,0,0,0,0,1,0,0,0,1,1], 24:[0,0,0,0,1,1,0,1,0,0,1,1], 25:[0,0,0,0,1,1,1,1,0,0,0,1], #Raised mild slopes
                        26:[1,0,0,0,0,0,1,1,0,0,0,0], 27:[0,1,0,0,0,0,0,0,0,0,1,1], 28:[0,0,0,0,0,1,0,0,0,0,1,1], 29:[0,0,0,0,1,0,1,1,0,0,0,0], #Short steep slopes
                        30:[1,1,0,0,1,0,1,1,0,0,0,0], 31:[1,1,0,0,0,1,0,0,0,0,1,1], 32:[0,1,0,0,1,1,0,0,0,0,1,1], 33:[1,0,0,0,1,1,1,1,0,0,0,0]} #Raised steep slopes

    #put each segment in its correct cell
    for coord, tile_id in tile_dic.items():
        xcoord = coord[0]
        ycoord = coord[1]
        if tile_id > 33:
            tile_id = 0
        grid_edge_list = tile_grid_edge_map[tile_id]
        segment_list = tile_segment_map[tile_id]
        for y in range(3):
            for x in range(2):
                hor_grid_edge_dic[(2*xcoord + x, 2*ycoord + y)] += grid_edge_list[2*y + x]
                hor_segment_dic[(2*xcoord + x, 2*ycoord + y)] += segment_list[2*y + x]
        for x in range(3):
            for y in range(2):
                ver_grid_edge_dic[(2*xcoord + x, 2*ycoord + y)] += grid_edge_list[2*x + y + 6]
                ver_segment_dic[(2*xcoord + x, 2*ycoord + y)] += segment_list[2*x + y + 6]
        xtl = xcoord * 24
        ytl = ycoord * 24
        if tile_id in (6, 8):
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl)))
        if tile_id in (7, 9): 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl+24)))
        if tile_id == 10:
            segment_dic[coord].append(GridSegmentCircular((xtl, ytl), (1, 1)))
        if tile_id == 11: 
            segment_dic[coord].append(GridSegmentCircular((xtl+24, ytl), (-1, 1)))
        if tile_id == 12: 
            segment_dic[coord].append(GridSegmentCircular((xtl+24, ytl+24), (-1, -1)))
        if tile_id == 13: 
            segment_dic[coord].append(GridSegmentCircular((xtl, ytl+24), (1, -1)))
        if tile_id == 14:
            segment_dic[coord].append(GridSegmentCircular((xtl+24, ytl+24), (-1, -1), convex=False))
        if tile_id == 15: 
            segment_dic[coord].append(GridSegmentCircular((xtl, ytl+24), (1, -1), convex=False))
        if tile_id == 16: 
            segment_dic[coord].append(GridSegmentCircular((xtl, ytl), (1, 1), convex=False))
        if tile_id == 17: 
            segment_dic[coord].append(GridSegmentCircular((xtl+24, ytl), (-1, 1), convex=False))
        if tile_id in (18, 24):
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+12), (xtl+24, ytl)))
        if tile_id in (19, 25):
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+24, ytl+12)))
        if tile_id in (20, 22): 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+24, ytl+12)))
        if tile_id in (21, 23): 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+12), (xtl+24, ytl+24)))
        if tile_id in (26, 32):
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+24), (xtl+12, ytl)))
        if tile_id in (27, 33): 
            segment_dic[coord].append(GridSegmentLinear((xtl+12, ytl), (xtl+24, ytl+24)))
        if tile_id in (28, 30): 
            segment_dic[coord].append(GridSegmentLinear((xtl+12, ytl+24), (xtl+24, ytl)))
        if tile_id in (29, 31): 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+12, ytl+24)))
    for coord, state in hor_segment_dic.items():
        if state == 1:
            xcoord = coord[0]
            ycoord = coord[1]
            segment_dic[(math.floor(xcoord/2), math.floor(ycoord/2))].append(GridSegmentLinear((12*xcoord, 12*ycoord), (12*xcoord+12, 12*ycoord)))
    for coord, state in ver_segment_dic.items():
        if state == 1:
            xcoord = coord[0]
            ycoord = coord[1]
            segment_dic[(math.floor(xcoord/2), math.floor(ycoord/2))].append(GridSegmentLinear((12*xcoord, 12*ycoord), (12*xcoord, 12*ycoord+12)))
    
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
        if type == 10:
            EntityLaunchPad(type, xcoord, ycoord, orientation)
        if type == 11:
            EntityOneWayPlatform(type, xcoord, ycoord, orientation)
        if type == 17:
            EntityBounceBlock(type, xcoord, ycoord)
        if type == 20:
            EntityThwump(type, xcoord, ycoord, orientation)
        if type == 24:
            EntityBoostPad(type, xcoord, ycoord)
        if type == 28:
            EntityShoveThwump(type, xcoord, ycoord)
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
    lines = []
    for cell in segment_dic.values():
        for segment in cell:
            if segment.type == "linear":
                lines.append([(segment.x1, segment.y1), (segment.x2, segment.y2)])
    lc = mc.LineCollection(lines)
    ax.add_collection(lc)
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


