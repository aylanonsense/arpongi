pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

--[[

platform channels:
	1:	level bounds
	2:	commander
]]

-- convenient no-op function that does nothing
function noop() end

local level_bounds={
	top={x=0,y=20,vx=0,vy=0,width=128,height=0,platform_channel=1},
	left={x=1,y=0,vx=0,vy=0,width=0,height=128,platform_channel=1},
	bottom={x=0,y=108,vx=0,vy=0,width=128,height=0,platform_channel=1},
	right={x=127,y=0,vx=0,vy=0,width=0,height=128,platform_channel=1}
}

local entities
local buttons={}
local button_presses={}

local entity_classes={
	commander={
		width=4,
		height=15,
		collision_indent=1,
		move_y=0,
		platform_channel=2,
		update=function(self)
			-- move vertically
			self.move_y=ternary(btn(3,self.player_num),1,0)-ternary(btn(2,self.player_num),1,0)
			self.vy=2*self.move_y
			self:apply_velocity()
			-- keep in bounds
			self.y=mid(level_bounds.top.y,self.y,level_bounds.bottom.y-self.height)
		end
	},
	ball={
		width=4,
		height=4,
		collision_indent=1,
		vx=1,
		vy=1,
		collision_channel=1 + 2, -- level bounds + commanders
		update=function(self)
			self:apply_velocity(true)
		end,
		on_collide=function(self,dir,other)
			if other.class_name!="commander" or (other.x<64 and dir=="left") or (other.x>64 and dir=="right") then
				self:handle_collision_position(dir,other)
				-- bounce!
				if (dir=="left" and self.vx<0) or (dir=="right" and self.vx>0) then
					self.vx*=-1
				elseif (dir=="up" and self.vy<0) or (dir=="down" and self.vy>0) then
					self.vy*=-1
				end
			end
		end
	}
}

function _init()
	entities={}
	spawn_entity("commander",level_bounds.left.x+5,60,{player_num=1})
	spawn_entity("commander",level_bounds.right.x-5-entity_classes.commander.width,60,{player_num=0})
	spawn_entity("ball",50,50)
end

-- local skip_frames=0
-- local was_paused=false
function _update(is_paused)
	-- skip_frames+=1
	-- if skip_frames%10>0 and not btn(5) then return end
	-- keep track of button presses
	local i
	for i=0,5 do
		button_presses[i]=btn(i) and not buttons[i]
		buttons[i]=btn(i)
	end
	-- update all the entities
	local entity
	for entity in all(entities) do
		increment_counter_prop(entity,"frames_alive")
		entity:update()
	end
	-- check for hits
	for i=1,#entities do
		local j
		for j=1,#entities do
			if i!=j and entities[i]:is_hitting(entities[j]) then
				entities[i]:on_hit(entities[j])
				entities[j]:on_hurt(entities[i])
			end
		end
	end
	-- remove dead entities
	for entity in all(entities) do
		if not entity.is_alive then
			del(entities,entity)
		end
	end
end

-- local was_paused=false
-- function _paused()
-- end

function _draw()
	camera()
	-- clear the screen
	cls(1)
	-- draw the level bounds
	rect(level_bounds.left.x+0.5,level_bounds.top.y+0.5,level_bounds.right.x-0.5,level_bounds.bottom.y-0.5,2)
	-- draw the entities
	local entity
	for entity in all(entities) do
		entity:draw()
		pal()
	end
end

-- spawns an entity that's an instance of the given class
function spawn_entity(class_name,x,y,args)
	local class_def=entity_classes[class_name]
	-- create a default entity
	local entity={
		class_name=class_name,
		frames_alive=0,
		is_alive=true,
		x=x,
		y=y,
		vx=0,
		vy=0,
		width=8,
		height=8,
		collision_indent=2,
		collision_padding=0,
		collision_channel=0,
		platform_channel=0,
		hit_channel=0,
		hurt_channel=0,
		init=noop,
		update=function(self)
			self:apply_velocity()
		end,
		apply_velocity=function(self,stop_after_collision)
			-- move in discrete steps if we might collide with something
			if self.collision_channel>0 then
				local max_move_x=min(self.collision_indent,self.width-2*self.collision_indent)-0.1
				local max_move_y=min(self.collision_indent,self.height-2*self.collision_indent)-0.1
				local steps=max(1,ceil(max(abs(self.vx/max_move_x),abs(self.vy/max_move_y))))
				local i
				for i=1,steps do
					-- apply velocity
					self.x+=self.vx/steps
					self.y+=self.vy/steps
					-- check for collisions
					if self:check_for_collisions() and stop_after_collision then
						return
					end
				end
			-- just move all at once
			else
				self.x+=self.vx
				self.y+=self.vy
			end
		end,
		-- hit functions
		is_hitting=function(self,other)
			return band(self.hit_channel,other.hurt_channel)>0 and objects_overlapping(self,other)
		end,
		on_hit=noop,
		on_hurt=noop,
		-- collision functions
		check_for_collisions=function(self)
			local found_collision=false
			-- check for collisions against other entities
			local entity
			for entity in all(entities) do
				if entity!=self then
					local collision_dir=self:check_for_collision(entity)
					if collision_dir then
						-- they are colliding!
						self:on_collide(collision_dir,entity)
						found_collision=true
					end
				end
			end
			-- check for collisions against the level boundaries
			if band(self.collision_channel,1)>0 then
				if self.y+self.height+self.collision_padding>level_bounds.bottom.y then
					self:on_collide("down",level_bounds.bottom)
					found_collision=true
				elseif self.x+self.width+self.collision_padding>level_bounds.right.x then
					self:on_collide("right",level_bounds.right)
					found_collision=true
				elseif self.x-self.collision_padding<level_bounds.left.x then
					self:on_collide("left",level_bounds.left)
					found_collision=true
				elseif self.y-self.collision_padding<level_bounds.top.y then
					self:on_collide("up",level_bounds.top)
					found_collision=true
				end
			end
			return found_collision
		end,
		check_for_collision=function(self,other)
			if band(self.collision_channel,other.platform_channel)>0 then
				return objects_colliding(self,other)
			end
		end,
		on_collide=function(self,dir,other)
			self:handle_collision_position(dir,other)
			self:handle_collision_velocity(dir,other)
		end,
		handle_collision_position=function(self,dir,other)
			if dir=="left" then
				self.x=other.x+other.width
			elseif dir=="right" then
				self.x=other.x-self.width
			elseif dir=="up" then
				self.y=other.y+other.height
			elseif dir=="down" then
				self.y=other.y-self.height
			end
		end,
		handle_collision_velocity=function(self,dir,other)
			if dir=="left" then
				self.vx=max(self.vx,other.vx)
			elseif dir=="right" then
				self.vx=min(self.vx,other.vx)
			elseif dir=="up" then
				self.vy=max(self.vy,other.vy)
			elseif dir=="down" then
				self.vy=min(self.vy,other.vy)
			end
		end,
		-- draw functions
		draw=function(self)
			self:draw_outline()
		end,
		draw_outline=function(self,color)
			rect(self.x+0.5,self.y+0.5,self.x+self.width-0.5,self.y+self.height-0.5,color or 7)
		end,
		-- lifetime functions
		die=function(self)
			if self.is_alive then
				self.is_alive=false
				self:on_death()
			end
		end,
		on_death=noop
	}
	-- add class-specific properties
	local key,value
	for key,value in pairs(class_def) do
		entity[key]=value
	end
	-- override with passed-in arguments
	for key,value in pairs(args or {}) do
		entity[key]=value
	end
	-- add it to the list of entities
	add(entities,entity)
	-- initialize the entitiy
	entity:init()
	-- return the new entity
	return entity
end

-- check to see if two rectangles are overlapping
function rects_overlapping(x1,y1,w1,h1,x2,y2,w2,h2)
	return x1<x2+w2 and x2<x1+w1 and y1<y2+h2 and y2<y1+h1
end

-- check to see if obj1 is overlapping with obj2
function objects_overlapping(obj1,obj2)
	return rects_overlapping(obj1.x,obj1.y,obj1.width,obj1.height,obj2.x,obj2.y,obj2.width,obj2.height)
end

-- check to see if obj1 is colliding into obj2, and if so in which direction
function objects_colliding(obj1,obj2)
	local x1,y1,w1,h1,i,p=obj1.x,obj1.y,obj1.width,obj1.height,obj1.collision_indent,obj1.collision_padding
	local x2,y2,w2,h2=obj2.x,obj2.y,obj2.width,obj2.height
	-- check hitboxes
	if rects_overlapping(x1+i,y1+h1/2,w1-2*i,h1/2+p,x2,y2,w2,h2) and obj1.vy>=obj2.vy then
		return "down"
	elseif rects_overlapping(x1+w1/2,y1+i,w1/2+p,h1-2*i,x2,y2,w2,h2) and obj1.vx>=obj2.vx then
		return "right"
	elseif rects_overlapping(x1-p,y1+i,w1/2+p,h1-2*i,x2,y2,w2,h2) and obj1.vx<=obj2.vx then
		return "left"
	elseif rects_overlapping(x1+i,y1-p,w1-2*i,h1/2+p,x2,y2,w2,h2) and obj1.vy<=obj2.vy then
		return "up"
	end
end

-- returns the second argument if condition is truthy, otherwise returns the third argument
function ternary(condition,if_true,if_false)
	return condition and if_true or if_false
end

-- increment a counter, wrapping to 20000 if it risks overflowing
function increment_counter(n)
	return ternary(n>32000,20000,n+1)
end

-- increment_counter on a property of an object
function increment_counter_prop(obj,key)
	obj[key]=increment_counter(obj[key])
end

-- decrement a counter but not below 0
function decrement_counter(n)
	return max(0,n-1)
end

-- decrement_counter on a property of an object, returns true when it reaches 0
function decrement_counter_prop(obj,key)
	local initial_value=obj[key]
	obj[key]=decrement_counter(initial_value)
	return initial_value>0 and initial_value<=1
end

__gfx__
00000000000777000000000000000000777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000777700077700000777000700000700700070000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000700000700070007777700700000700070700000000000000000000000000000000000000000000000000000000000000000000000000000000000
00050000000700000700070007777700700000700007000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000700000700070007777700700000700070700000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000077700000777000700000700700070000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
