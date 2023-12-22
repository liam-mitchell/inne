import matplotlib.pyplot as mpl
from itertools import product
import math
import os.path
import zlib

'''
    TODO:

    - Since all bytes from the map data are casted to integers individually,
      the 2-byte object counts aren't read correctly, so this will fail for
      levels with over 256 exit doors, for example.
    - Generalize to more than 4 players (only Mpl left to adapt)
'''

'''
    Constants
'''

# Configure ntrace's input and output. They must be True when using with outte!
OUTTE_MODE        = True # Format output for outte's usage.
COMPRESSED_INPUTS = True # Inputs are Zlibbed.

# Filenames. Keep original names when running with outte.
FILE_INPUTS_LEVEL   = "inputs_%d"
FILE_INPUTS_EPISODE = "inputs_episode"
FILE_MAP_LEVEL      = "map_data"
FILE_MAP_EPISODE    = "map_data_%d"
MAP_IMG             = "screenshot.PNG" # Only needed for manual execution

# Physics constants
GRAVITY              = 0.06666666666666665
GRAVITY_HELD         = 0.01111111111111111
GROUND_ACCEL         = 0.06666666666666665
AIR_ACCEL            = 0.04444444444444444
DRAG                 = 0.9933221725495059 # 0.99^(2/3)
FRICTION_GROUND      = 0.9459290248857720 # 0.92^(2/3)
FRICTION_GROUND_SLOW = 0.8617738760127536 # 0.80^(2/3)
FRICTION_WALL        = 0.9113380468927672 # 0.87^(2/3)
MAX_XSPEED           = 3.333333333333333

FPS = 60

# Map data parameters
OFFSET_MODE    =   12
OFFSET_TITLE   =   38
OFFSET_TILES   =  184
OFFSET_COUNTS  = 1150
OFFSET_OBJECTS = 1230

IDS = {
    'ninja'          :  0, 'mine'             :  1, 'gold'        :  2, 'exit_door'          :  3,
    'exit_switch'    :  4, 'door_regular'     :  5, 'door_locked' :  6, 'door_locked_switch' :  7,
    'door_trap'      :  8, 'door_trap_switch' :  9, 'launch_pad'  : 10, 'one_way'            : 11,
    'drone_chaingun' : 12, 'drone_laser'      : 13, 'drone_zap'   : 14, 'drone_chaser'       : 15,
    'floor_guard'    : 16, 'bounce_block'     : 17, 'rocket'      : 18, 'gauss'              : 19,
    'thwump'         : 20, 'toggle_mine'      : 21, 'evil_ninja'  : 22, 'laser_turret'       : 23,
    'boost_pad'      : 24, 'death_ball'       : 25, 'micro_drone' : 26, 'mini'               : 27,
    'shove_thwump'   : 28, 'player_rocket'    : 29
}

# Dimensions
UNITS   = 24
ROWS    = 23
COLUMNS = 42

RADIUS = {
    'ninja'          : 10, 'mine'             :  4, 'gold'        :   6, 'exit_door'          :  12,
    'exit_switch'    :  6, 'door_regular'     : 10, 'door_locked' :  12, 'door_locked_switch' :   5,
    'door_trap'      : 12, 'door_trap_switch' :  5, 'launch_pad'  :   6, 'one_way'            :  12,
    'drone_chaingun' :  0, 'drone_laser'      :  0, 'drone_zap'   : 7.5, 'drone_chaser'       : 7.5,
    'floor_guard'    :  6, 'bounce_block'     :  9, 'rocket'      :   0, 'gauss'              :   0,
    'thwump'         :  9, 'toggle_mine'      :  4, 'evil_ninja'  :  10, 'laser_turret'       :   0,
    'boost_pad'      :  6, 'death_ball'       :  5, 'micro_drone' :   4, 'mini'               :   5,
    'shove_thwump'   : 12, 'player_rocket'    :  0
}

# Other constants
MAX_PLAYERS  = 4
INPUT_SEP    = b'&'
INPUT_OFFSET = 215
INITIAL_TIME = 90

# Import inputs
inputs_list = []
if os.path.isfile(FILE_INPUTS_EPISODE):
    tool_mode = "splits"
    with open(FILE_INPUTS_EPISODE, "rb") as f:
        inputs_episode = zlib.decompress(f.read()).split(INPUT_SEP)
        for inputs_level in inputs_episode:
            inputs_list.append([int(b) for b in inputs_level])
else:
    tool_mode = "trace"
    for i in range(MAX_PLAYERS):
        if not os.path.isfile(FILE_INPUTS_LEVEL % i): break
        with open(FILE_INPUTS_LEVEL % i, "rb") as f:
            if COMPRESSED_INPUTS:
                inputs_list.append([int(b) for b in zlib.decompress(f.read())])
            else:
                inputs_list.append([int(b) for b in f.read()[INPUT_OFFSET:]])

# Import map data
mdata_list = []
if tool_mode == "trace":
    with open(FILE_MAP_LEVEL, "rb") as f:
        mdata = [int(b) for b in f.read()]
    mdata_list = [mdata] * len(inputs_list)
elif tool_mode == "splits":
    for i in range(5):
        with open(FILE_MAP_EPISODE % i, "rb") as f:
            mdata_list.append([int(b) for b in f.read()])

class Ninja:
    """This class is responsible for updating and storing the positions and velocities of each ninja.
    self.poslog contains all the coordinates used to generate the traces of the replays.
    """
    def __init__(self, xspawn, yspawn):
        """Initiate ninja position at spawn point, and initiate other values to their initial state"""
        self.xpos              = xspawn
        self.ypos              = yspawn
        self.xspeed            = 0
        self.yspeed            = 0
        self.xspeed_old        = 0
        self.yspeed_old        = 0
        self.applied_gravity   = GRAVITY
        self.applied_friction  = FRICTION_GROUND
        self.grounded          = False
        self.grounded_old      = False
        self.ground_normal     = (0, -1)
        self.ground_sliding    = 0
        self.walled            = False
        self.wall_normal       = 0
        self.wall_sliding      = 0
        self.pre_buffer        = 0
        self.post_buffer       = 0
        self.post_buffer_wall  = 0
        self.jump_held_time    = 0
        self.jumping           = False
        self.wall_jumping      = False
        self.gravity_held_time = 0
        self.hor_input         = 0
        self.jump_input        = 0
        self.hor_input_old     = 0
        self.poslog            = [(0, xspawn, yspawn)]
        self.xposlog           = [xspawn]
        self.yposlog           = [yspawn]
        self.speedlog          = [(0, 0, 0)]
        self.plog              = [(0, 0)]
        self.radius            = RADIUS['ninja']

    def center_cell(self):
        """find the cell coordinates containing the center of the ninja at its current x and y pos"""
        return (math.floor(self.xpos / UNITS), math.floor(self.ypos / UNITS))
    
    def neighbour_cells(self, radius):
        """Return a set containing all cells that the ninja overlaps.
        There can be either 1, 2 or 4 cells in the neighbourhood
        """
        pairs = product((self.xpos, self.ypos), (-radius, radius))
        x1, x2, y1, y2 = (math.floor((p + r) / UNITS) for p, r in pairs)
        return set(product((x1, x2), (y1, y2)))
    
    def object_neighbour_cells(self):
        """Return a list that contains all the cells that could contain objects which the ninja could interact with.
        This list contains nine cells. The one containing the center of the ninja and the eight cells around it.
        """
        cx, cy = self.center_cell()
        return product(range(cx - 1, cx + 2), range(cy - 1, cy + 2))
    
    def pre_collision(self):
        """Update the speeds and positions of the ninja before the collision phase."""
        self.xspeed_old = self.xspeed
        self.yspeed_old = self.yspeed
        self.xspeed *= DRAG
        self.yspeed *= DRAG
        self.yspeed += self.applied_gravity
        self.xpos += self.xspeed
        self.ypos += self.yspeed
        self.grounded_old = self.grounded
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
        self.xspeed += self.hor_input * (GROUND_ACCEL if self.grounded else AIR_ACCEL)
        if abs(self.xspeed) > MAX_XSPEED:
            self.xspeed = xspeed_pc

        #Check if walled
        neighbour_cells = self.neighbour_cells(self.radius + 0.1)
        for cell in neighbour_cells:
            for segment in segment_dic[cell]:
                if segment.active:
                    is_walled = segment.is_wall_intersecting(self) if segment.type == "linear" else False
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
        if (self.hor_input == 0 or self.hor_input * self.xspeed < 0) and self.grounded:
            self.ground_sliding += (1 if self.grounded_old else 2)
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

        #Apply ground friction if applicable
        if self.grounded and self.ground_sliding > 1:
            if abs(self.xspeed) <= 0.1 and (self.hor_input or abs(self.xspeed_old) > 0.1):
                self.applied_friction = 1
            if self.ground_normal == (0, -1): #regular friction formula for flat ground.
                self.xspeed *= self.applied_friction
            elif self.yspeed > 0: #friction going down a slope
                self.xspeed *= FRICTION_GROUND
            elif self.yspeed < 0:
            #This is the worst friction formula ever concieved. For when the ninja is sliding on a slope upwards.
                speed_scalar = math.sqrt(self.xspeed**2 + self.yspeed**2)
                fric_force = abs(self.xspeed * (1-FRICTION_GROUND) * self.ground_normal[1])
                fric_force2 = speed_scalar - fric_force * self.ground_normal[1]**2
                self.xspeed = self.xspeed / speed_scalar * fric_force2
                self.yspeed = self.yspeed / speed_scalar * fric_force2
            if abs(self.xspeed) <= 0.1:
                self.applied_friction = (1 if self.hor_input else FRICTION_GROUND_SLOW)
        if abs(self.xspeed) > 0.1:
            self.applied_friction = FRICTION_GROUND

        #Apply wall friction if applicable
        if self.wall_sliding > 1:
            self.yspeed *= FRICTION_WALL

        #If the ninja is in the state of jumping and holding the jump key, lower his applied gravity. Ignore held jump after 46 frames
        self.applied_gravity = (GRAVITY_HELD if 1 <= self.gravity_held_time <= 46 else GRAVITY)
        if not self.jump_input:
            self.jumping = False
            self.wall_jumping = False 

        self.hor_input_old = self.hor_input

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
    
class GridSegmentCircular:
    """Contains all the circular segments of tiles that the ninja can interract with"""
    def __init__(self, center, quadrant, convex=True, radius=UNITS):
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
        self.cell = (math.floor(self.xpos / UNITS), math.floor(self.ypos / UNITS))
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
        self.cell = (math.floor(self.xpos / UNITS), math.floor(self.ypos / UNITS))
        entity_dic[self.cell].append(self)

class EntityGold(Entity):
    def __init__(self, type, xcoord, ycoord):
        super().__init__(type, xcoord, ycoord)
        self.is_logical_collidable = True
        self.radius = RADIUS['gold']
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
        self.radius = RADIUS['exit_door']
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
        self.radius = RADIUS['exit_switch']
        self.collected = False
        self.parent = parent

    def logical_collision(self, ninja):
        """If the ninja is colliding with the switch, flag it as being collected, and open its associated door."""
        if self.is_colliding_circle(ninja):
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
            self.segment = GridSegmentLinear((self.xpos, self.ypos-UNITS / 2), (self.xpos, self.ypos+UNITS / 2))
        if orientation == 2:
            self.segment = GridSegmentLinear((self.xpos-UNITS / 2, self.ypos), (self.xpos+UNITS / 2, self.ypos))
        segment_dic[self.cell].append(self.segment)
        self.xpos = self.sw_xpos
        self.ypos = self.sw_ypos
        self.grid_move()

    def change_state(self, open=True):
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
        self.radius = RADIUS['door_regular']
        self.open_timer = 0

    def think(self):
        if self.open:
            self.open_timer += 1
            if self.open_timer > 5:
                self.change_state(open=False)

    def logical_collision(self, ninja):
        if self.is_colliding_circle(ninja):
            self.change_state()
            self.open_timer = 0

class EntityDoorLocked(EntityDoorBase):
    def __init__(self, type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord):
        super().__init__(type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord)
        self.radius = RADIUS['door_locked_switch']

    def logical_collision(self, ninja):
        if self.is_colliding_circle(ninja):
            self.change_state()
            self.active = False

class EntityDoorTrap(EntityDoorBase):
    def __init__(self, type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord):
        super().__init__(type, xcoord, ycoord, orientation, sw_xcoord, sw_ycoord)
        self.radius = RADIUS['door_trap_switch']
        self.open = True
        self.segment.active = False

    def logical_collision(self, ninja):
        if self.is_colliding_circle(ninja):
            self.change_state(open=False)
            self.active = False
            
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
        self.semiside = RADIUS['bounce_block']
        self.stiffness = 0.02222222222222222
        self.dampening = 0.98
        self.strength = 0.2
        self.is_immobile = True
        
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

class EntityBoostPad(Entity):
    def __init__(self, type, xcoord, ycoord):
        super().__init__(type, xcoord, ycoord)
        self.is_movable = True
        self.radius = RADIUS['boost_pad']
        self.is_touching_ninja = False

    def move(self, ninja):
        if self.is_colliding_circle(ninja):
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
    dot_prod = p.xspeed * dx + p.yspeed * dy #negative dot prod means the ninja is moving towards the point else away from it
    xspeed_boost = 0
    if p.xspeed * dx < 0 and dy < 0 and p.xspeed * p.hor_input > 0 and p.hor_input_old == p.hor_input and not (p.pre_buffer and not p.jumping):
        if p.xspeed > 0:
            xspeed_boost = 1/30
        if p.xspeed < 0:
            xspeed_boost = -1/30
    if dot_prod < 0: #check if you're moving towards the corner.
        xspeed_new = (p.xspeed*dy - p.yspeed*dx) / dist**2 * dy
        yspeed_new = (p.xspeed*dy - p.yspeed*dx) / dist**2 * (-dx)
        xspeed_new_boost = ((p.xspeed+xspeed_boost)*dy - p.yspeed*dx) / dist**2 * dy
        yspeed_new_boost = ((p.xspeed+xspeed_boost)*dy - p.yspeed*dx) / dist**2 * (-dx)
        if p.xspeed * xspeed_new_boost < 0 and abs(xspeed_new_boost) >= abs(xspeed_boost):
            p.xspeed = xspeed_new	
            p.yspeed = yspeed_new
        else:
            p.xspeed = xspeed_new_boost	
            p.yspeed = yspeed_new_boost
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
            entity.move(p)

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
                if segment.active:
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
    tile_data = mdata[OFFSET_TILES:OFFSET_TILES + ROWS * COLUMNS]

    #initiate a dictionary mapping each tile to its cell. Start by filling it with full tiles.
    tile_dic = {}
    for x in range(COLUMNS + 2):
        for y in range(ROWS + 2):
            tile_dic[(x, y)] = 1

    #map each tile to its cell
    for x in range(COLUMNS):
        for y in range(ROWS):
            tile_dic[(x+1, y+1)] = tile_data[x + y*COLUMNS]

    segment_dic = {}
    for x in range(COLUMNS + 2):
        for y in range(ROWS + 2):
            segment_dic[(x, y)] = []
    entity_dic = {}
    for x in range(COLUMNS + 2):
        for y in range(ROWS + 2):
            entity_dic[(x, y)] = []
    entity_list = []

    #put each segment in its correct cell
    for coord, tile_id in tile_dic.items():
        xtl = coord[0] * UNITS
        ytl = coord[1] * UNITS
        if tile_id == 1: #1: full tile
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS)))
        if tile_id == 2: #2-5: half tiles
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS / 2), (xtl+UNITS, ytl+UNITS / 2)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS / 2)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS / 2)))
        if tile_id == 3:
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS / 2, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS / 2, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS / 2, ytl), (xtl+UNITS / 2, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS)))
        if tile_id == 4:
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS / 2), (xtl+UNITS, ytl+UNITS / 2)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS / 2), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl+UNITS / 2), (xtl+UNITS, ytl+UNITS)))
        if tile_id == 5:
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS / 2, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS / 2, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS / 2, ytl), (xtl+UNITS / 2, ytl+UNITS)))
        if tile_id == 6: #6-9: 45 degreee slopes
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl)))
        if tile_id == 7: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl+UNITS)))
        if tile_id == 8: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl)))
        if tile_id == 9: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl+UNITS)))
        if tile_id == 10: #10-13: quarter moons
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentCircular((xtl, ytl), (1, 1)))
        if tile_id == 11: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentCircular((xtl+UNITS, ytl), (-1, 1)))
        if tile_id == 12: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentCircular((xtl+UNITS, ytl+UNITS), (-1, -1)))
        if tile_id == 13: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentCircular((xtl, ytl+UNITS), (1, -1)))
        if tile_id == 14: #14-17: quarter pipes
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentCircular((xtl+UNITS, ytl+UNITS), (-1, -1), convex=False))
        if tile_id == 15: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentCircular((xtl, ytl+UNITS), (1, -1), convex=False))
        if tile_id == 16: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentCircular((xtl, ytl), (1, 1), convex=False))
        if tile_id == 17: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentCircular((xtl+UNITS, ytl), (-1, 1), convex=False))
        if tile_id == 18: #18-21: short mild slopes
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS / 2)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS / 2), (xtl+UNITS, ytl)))
        if tile_id == 19:
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS / 2)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl+UNITS / 2)))
        if tile_id == 20: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl+UNITS / 2), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS / 2)))
        if tile_id == 21: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS / 2), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS / 2), (xtl+UNITS, ytl+UNITS)))
        if tile_id == 22: #22-25: raised mild slopes
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS / 2)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS / 2)))
        if tile_id == 23:
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS / 2)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS / 2), (xtl+UNITS, ytl+UNITS)))
        if tile_id == UNITS: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS / 2), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS / 2), (xtl+UNITS, ytl)))
        if tile_id == 25: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl+UNITS / 2), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl+UNITS / 2)))
        if tile_id == 26: #26-29: short steep slopes
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS / 2, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS / 2, ytl)))
        if tile_id == 27: 
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS / 2, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS / 2, ytl), (xtl+UNITS, ytl+UNITS)))
        if tile_id == 28: 
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS / 2, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS / 2, ytl+UNITS), (xtl+UNITS, ytl)))
        if tile_id == 29: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS / 2, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS / 2, ytl+UNITS)))
        if tile_id == 30: #30-33: raised steep slopes
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS / 2, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS / 2, ytl+UNITS), (xtl+UNITS, ytl)))
        if tile_id == 31: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS / 2, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS / 2, ytl+UNITS)))
        if tile_id == 32: 
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS / 2, ytl), (xtl+UNITS, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS, ytl), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS / 2, ytl)))
        if tile_id == 33: 
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl+UNITS / 2, ytl)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl+UNITS), (xtl+UNITS, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl, ytl), (xtl, ytl+UNITS)))
            segment_dic[coord].append(GridSegmentLinear((xtl+UNITS / 2, ytl), (xtl+UNITS, ytl+UNITS)))

    #find the spawn position of the ninja
    xspawn = mdata[OFFSET_OBJECTS + 1] * 6
    yspawn = mdata[OFFSET_OBJECTS + 2] * 6

    #initiate player 1 instance of Ninja at spawn coordinates
    p1 = Ninja(xspawn, yspawn)

    #Initiate each entity (other than ninjas)
    index = OFFSET_OBJECTS
    exit_door_count = mdata[OFFSET_COUNTS + 2 * IDS['exit_door']]
    while (True):
        type = mdata[index]
        xcoord = mdata[index+1]
        ycoord = mdata[index+2]
        orientation = mdata[index+3]
        mode = mdata[index+4]
        if type == IDS['gold']:
            EntityGold(type, xcoord, ycoord)
        if type == IDS['exit_door']:
            parent = EntityExit(type, xcoord, ycoord)
            child_xcoord = mdata[index + 5*exit_door_count + 1]
            child_ycoord = mdata[index + 5*exit_door_count + 2]
            EntityExitSwitch(4, child_xcoord, child_ycoord, parent)
        if type == IDS['door_regular']:
            EntityDoorRegular(type, xcoord, ycoord, orientation, xcoord, ycoord)
        if type == IDS['door_locked']:
            switch_xcoord = mdata[index + 6]
            switch_ycoord = mdata[index + 7]
            EntityDoorLocked(type, xcoord, ycoord, orientation, switch_xcoord, switch_ycoord)
        if type == IDS['door_trap']:
            switch_xcoord = mdata[index + 6]
            switch_ycoord = mdata[index + 7]
            EntityDoorTrap(type, xcoord, ycoord, orientation, switch_xcoord, switch_ycoord)
        if type == IDS['bounce_block']:
            EntityBounceBlock(type, xcoord, ycoord)
        if type == IDS['boost_pad']:
            EntityBoostPad(type, xcoord, ycoord)
        index += 5
        if index >= len(mdata):
            break

    #Execute the main physics function once per frame
    for frame in range(1, inp_len+1):
        tick(p1, frame)

    xposlog.append(p1.xposlog)
    yposlog.append(p1.yposlog)

    if tool_mode == "splits":
        gold_amount = mdata[OFFSET_COUNTS + 2 * IDS['gold']]
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

    if not OUTTE_MODE:
        print(p1.speedlog)
        #print(p1.poslog)
        print(valid_replay)

#Plot the route. Only ran in manual mode.
if tool_mode == "trace" and OUTTE_MODE == False:
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
    if MAP_IMG:
        img = mpl.imread(MAP_IMG)
        ax.imshow(img, extent=[0, 1056, 600, 0])
    mpl.show()

#For each replay, write to file whether it is valid or not, then write the series of coordinates for each frame. Only ran in outte mode and in trace mode.
if tool_mode == "trace" and OUTTE_MODE == True:
    with open("output.txt", "w") as f:
        for i in range(len(inputs_list)):
            print(validlog[i], file=f)
            for frame in range(len(xposlog[i])):
                print(round(xposlog[i][frame], 2), round(yposlog[i][frame], 2), file=f)

#Print episode splits and other info to the console. Only ran in manual mode and splits mode.
if tool_mode == "splits" and OUTTE_MODE == False:
    print("SI-A-00 0th replay analysis:")
    split = INITIAL_TIME * FPS
    for i in range(5):
        split = split - frameslog[i] + 1 + goldlog[i][0] * 2 * FPS
        split_score = round(split/FPS, 3)
        print(f"{i}:-- Is replay valid?: {validlog[i]} | Gold collected: {goldlog[i][0]}/{goldlog[i][1]} | Replay length: {frameslog[i]} frames | Split score: {split_score:.3f}")

#For each level of the episode, write to file whether the replay is valid, then write the score split. Only ran in outte mode and in splits mode.
if tool_mode == "splits" and OUTTE_MODE == True:
    split = INITIAL_TIME * FPS
    with open("output.txt", "w") as f:
        for i in range(5):
            print(validlog[i], file=f)
            split = split - frameslog[i] + 1 + goldlog[i][0] * 2 * FPS
            print(split, file=f)

