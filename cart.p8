pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

-- convenient no-op function that does nothing
function noop() end

local entities
local buttons={}
local button_presses={}

local entity_classes={}

function _init()
	entities={}
end

-- local skip_frames=0
function _update()
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

function _draw()
	camera()
	-- clear the screen
	cls(0)
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
		hit_channel=0,
		hurt_channel=0,
		init=noop,
		update=function(self)
			self:apply_velocity()
		end,
		apply_velocity=function(self)
			self.x+=self.vx
			self.y+=self.vy
		end,
		-- hit functions
		is_hitting=function(self,other)
			return band(self.hit_channel,other.hurt_channel)>0 and objects_overlapping(self,other)
		end,
		on_hit=noop,
		on_hurt=noop,
		-- draw functions
		draw=noop,
		draw_outline=function(self,color)
			rect(self.x+0.5,self.y+0.5,self.x+self.width-0.5,self.y+self.height-0.5,color)
		end,
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

-- returns the second argument if condition is truthy, otherwise returns the third argument
function ternary(condition,if_true,if_false)
	return condition and if_true or if_false
end

function increment_counter(n)
	return ternary(n>32000,2000,n+1)
end

function increment_counter_prop(obj,key)
	obj[key]=increment_counter(obj[key])
end

function decrement_counter(n)
	return max(0,n-1)
end

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
