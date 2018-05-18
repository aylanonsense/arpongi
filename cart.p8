pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

--[[

todo:
	buildings take damage / are triggered
	commanders take damage when the ball hits a side
	render layers

	the game ends when a commander reaches 0 hp
	the ball changes color / has a streak
	building over another building destroys it first
	gain gold
	troops
	paying for buildings costs money
	sound effects
	screen shake

	main menu
	lottery for the shared button
	character select
	music
	menu items are greyed out when unuseable
	gain xp
	leveling up
	upgrading buildings


platform channels:
	1:	level bounds
	2:	commander
]]

-- convenient no-op function that does nothing
function noop() end

local controllers={1,0}
local level_bounds={
	top={x=0,y=32,vx=0,vy=0,width=128,height=0,platform_channel=1},
	left={x=0,y=0,vx=0,vy=0,width=0,height=128,platform_channel=1,is_left_wall=true},
	bottom={x=0,y=105,vx=0,vy=0,width=128,height=0,platform_channel=1},
	right={x=127,y=0,vx=0,vy=0,width=0,height=128,platform_channel=1,is_right_wall=true}
}

local game_frames
local freeze_frames
local screen_shake_frames

local entities
local commanders
local buttons={{},{}}
local button_presses={{},{}}

local entity_classes={
	commander={
		width=2,
		height=15,
		collision_indent=0.5,
		move_y=0,
		platform_channel=2,
		is_commander=true,
		is_frozen=false,
		init=function(self)
			self.health=spawn_entity("health_counter",ternary(self.is_facing_left,100,10),4,{
				commander=self
			})
			self.gold=spawn_entity("gold_counter",ternary(self.is_facing_left,75,11),116,{
				commander=self
			})
			self.xp=spawn_entity("xp_counter",ternary(self.is_facing_left,100,36),116,{
				commander=self
			})
			self.plots=spawn_entity("plots",ternary(self.is_facing_left,76,20),36,{
				commander=self
			})
			local x=ternary(self.is_facing_left,92,24)
			self.primary_menu=spawn_entity("menu",x,63,{
				commander=self,
				menu_items={{1,"build"},{2,"upgrade"},{3,"cast spell"}},
				on_select=function(self,item,index)
					if index==1 then
						self.commander.build_menu:show()
						self:hide()
					end
				end
			})
			self.build_menu=spawn_entity("menu",x,63,{
				commander=self,
				menu_items={{4,"keep","+1 troop",100},{5,"farm","+3 gold",100},{6,"inn","+3 health",100}},
				on_select=function(self,item,index)
					self:hide()
					local location_menu=self.commander.location_menu
					location_menu.action="build"
					location_menu.build_choice=item
					location_menu:show(mid(1,flr(#location_menu.menu_items*(self.commander.y-20+self.commander.height/2)/75),#location_menu.menu_items))
				end
			})
			self.location_menu=spawn_entity("location_menu",x,63,{
				commander=self,
				menu_items=self.plots.locations,
				on_select=function(self,location)
					if self.action=="build" then
						if self.commander:build(self.build_choice[2],self.build_choice[4],location) then
							self:hide()
							self.commander.is_frozen=false
						end
					end
				end
			})
		end,
		update=function(self)
			-- activate the menu
			if not self.is_frozen and button_presses[self.player_num][4] then
				self.is_frozen=true
				button_presses[self.player_num][4]=false
				self.primary_menu:show()
			end
			-- move vertically
			if self.is_frozen then
				self.move_y=0
			else
				self.move_y=ternary(buttons[self.player_num][3],1,0)-ternary(buttons[self.player_num][2],1,0)
			end
			self.vy=self.move_y
			self:apply_velocity()
			-- keep in bounds
			self.y=mid(level_bounds.top.y-5,self.y,level_bounds.bottom.y-self.height+5)
		end,
		draw=function(self)
			-- draw paddle
			rectfill(self.x+0.5,self.y+0.5,self.x+self.width-0.5,self.y+self.height-0.5,self.colors[1])
			line(self.x+ternary(self.is_facing_left,0.5,1.5),self.y+0.5,self.x+ternary(self.is_facing_left,0.5,1.5),self.y+self.height-1.5,self.colors[3])
			-- draw commander
			pal(11,self.colors[2])
			pal(8,self.colors[2])
			pal(12,self.colors[2])
			if self.move_y!=0 then
				palt(ternary(self.frames_alive%10<5,12,8),true)
			end
			draw_sprite(4*self.sprite,0,4,6,self.x+ternary(self.is_facing_left,4,-6),self.y-4+flr(self.height/2),self.is_facing_left)
		end,
		draw_shadow=function(self)
			-- draw commander shadow
			local x,y=self.x+ternary(self.is_facing_left,3.5,-5.5),self.y+0.5+flr(self.height/2)
			rectfill(x,y,x+3,y+1,1)
			-- draw paddle shadow
			rectfill(self.x-0.5,self.y+1.5,self.x+self.width-1.5,self.y+self.height+0.5,1)
		end,
		build=function(self,building_type,cost,location)
			if self.gold.amount>=cost then
				self.gold.amount-=cost
				location.building=spawn_entity(building_type,location.x,location.y,{
					commander=self
				})
				return location.building
			end
		end
	},
	wizard={
		extends="commander",
		colors={13,12,12},
		sprite=0
	},
	thief={
		extends="commander",
		colors={9,10,10},
		sprite=1
	},
	knight={
		extends="commander",
		colors={8,8,14},
		sprite=2
	},
	counter={
		amount=0,
		displayed_amount=0,
		update=function(self)
			if self.displayed_amount<self.amount then
				self.displayed_amount=min(self.amount,self.displayed_amount+rnd_int(self.min_tick,self.max_tick))
			else
				self.displayed_amount=max(0,max(self.amount,self.displayed_amount-rnd_int(self.min_tick,self.max_tick)))
			end
		end,
		add=function(self,amt)
			self.amount+=amt
		end
	},
	health_counter={
		extends="counter",
		amount=50,
		displayed_amount=50,
		min_tick=1,
		max_tick=1,
		width=16,
		height=6,
		draw=function(self)
			draw_sprite(12,17,7,6,self.x,self.y)
			if self.displayed_amount<self.amount then
				color(11)
			elseif self.displayed_amount>self.amount then
				color(7)
			else
				color(8)
			end
			print(self.displayed_amount,self.x+9.5,self.y+1.5)
		end
	},
	gold_counter={
		extends="counter",
		min_tick=9,
		max_tick=16,
		width=17,
		height=5,
		draw=function(self)
			draw_sprite(19,18,4,5,self.x,self.y)
			pset(self.x+20.5,self.y+2.5,5)
			if self.displayed_amount<self.amount then
				color(10)
			elseif self.displayed_amount>self.amount then
				color(8)
			else
				color(7)
			end
			print(self.displayed_amount,self.x+6.5,self.y+0.5)
		end
	},
	xp_counter={
		amount=500,
		extends="counter",
		min_tick=18,
		max_tick=32,
		width=16,
		height=7,
		draw=function(self)
			draw_sprite(24,27,11,3,self.x,self.y+1)
			print("2",self.x+13.5,self.y+0.5,7)
			line(self.x+0.5,self.y+6.5,self.x+self.width-0.5,self.y+6.5,2)
			line(self.x+0.5,self.y+6.5,self.x+0.5+0.7*(self.width-1),self.y+6.5,14)
		end
	},
	pop_text={
		width=1,
		height=1,
		vy=-1.5,
		frames_to_death=32,
		update=function(self)
			self.vy+=0.1
			self:apply_velocity()
		end,
		draw=function(self)
			local text=""..self.amount
			local dx=0
			if self.type=="health" then
				draw_sprite(12,17,7,6,self.x-2*#text-5,self.y-6)
				color(8)
			elseif self.type=="xp" then
				dx=-7
				draw_sprite(35,27,7,4,self.x+2*#text-3,self.y-4)
				color(14)
			elseif self.type=="gold" then
				draw_sprite(19,18,4,5,self.x-2*#text-2,self.y-5)
				color(10)
			end
			print(text,self.x-2*#text+4.5+dx,self.y-4.5)
		end
	},
	plots={
		width=31,
		height=65,
		init=function(self)
			local x,y=self.x,self.y
			self.locations={
				{x=x+13,y=y},
				{x=x,y=y+13},
				{x=x+26,y=y+17},
				{x=x+13,y=y+30},
				{x=x,y=y+43},
				{x=x+26,y=y+47},
				{x=x+13,y=y+60}
			}
		end,
		draw=function(self)
			local loc
			for loc in all(self.locations) do
				-- draw_sprite(58,7,5,5,loc.x,loc.y)
				draw_sprite(16,15,3,2,loc.x+1,loc.y+1)
				-- pset(loc.x+2.5,loc.y+2.5,8)
			end
		end
	},
	menu={
		width=11,
		height=11,
		is_visible=false,
		highlighted_index=1,
		hint_counter=0,
		update=function(self)
			if self.is_visible then
				increment_counter_prop(self,"hint_counter")
				if button_presses[self.commander.player_num][2] then
					self.highlighted_index=ternary(self.highlighted_index==1,#self.menu_items,self.highlighted_index-1)
					self.hint_counter=0
				end
				if button_presses[self.commander.player_num][3] then
					self.highlighted_index=self.highlighted_index%#self.menu_items+1
					self.hint_counter=0
				end
				if button_presses[self.commander.player_num][4] then
					button_presses[self.commander.player_num][4]=false
					self:on_select(self.menu_items[self.highlighted_index],self.highlighted_index)
				end
				if button_presses[self.commander.player_num][5] then
					self:hide()
					self.commander.is_frozen=false
				end
			end
		end,
		draw=function(self)
			if self.is_visible then
				local y=self.y-5.5*#self.menu_items
				pal(1,0)
				pal(11,self.commander.colors[2])
				-- draw menu items
				local i
				for i=1,#self.menu_items do
					draw_sprite(0,6,11,12,self.x,y+10*i-4)
					draw_sprite(5+7*self.menu_items[i][1],0,7,7,self.x+2,y+10*i-2)
				end
				-- draw pointer
				self:render_pointer(self.x,y+10*self.highlighted_index-1,10)
				-- draw text box
				local curr_item=self.menu_items[self.highlighted_index]
				self:render_text(curr_item[2],curr_item[3],curr_item[4])
			end
		end,
		on_select=noop,
		show=function(self,starting_index)
			if not self.is_visible then
				self.is_visible=true
				self.highlighted_index=starting_index or 1
				self.hint_counter=0
			end
		end,
		hide=function(self)
			self.is_visible=false
		end,
		render_text=function(self,text,hint,gold)
			local x=ternary(self.commander.is_facing_left,64,1)
			draw_sprite(11,7,2,9,x,105)
			draw_sprite(13,7,1,9,x+2,105,false,false,58)
			draw_sprite(11,7,2,9,x+60,105,true)
			if hint and self.hint_counter%80>40 then
				print(hint,x+3.5,107.5,0)
			else
				print(text,x+3.5,107.5,0)
				if gold then
					print(gold,x+48.5,107+0.5,9)
				end
			end
		end,
		render_pointer=function(self,x,y,w)
			draw_sprite(16,7,13,8,x+ternary(self.commander.is_facing_left,(w or 0) + 2,-14),y,self.commander.is_facing_left)
		end
	},
	location_menu={
		extends="menu",
		draw=function(self)
			local loc=self.menu_items[self.highlighted_index]
			if self.is_visible then
				self:render_pointer(loc.x,loc.y,4)
			end
		end
	},
	ball={
		width=3,
		height=3,
		collision_indent=0.5,
		vx=0.75,
		vy=0,
		collision_channel=1 + 2, -- level bounds + commanders
		update=function(self)
			self:apply_velocity(true)
		end,
		draw=function(self)
			rectfill(self.x+0.5,self.y+0.5,self.x+self.width-0.5,self.y+self.height-0.5,7)
		end,
		draw_shadow=function(self)
			rectfill(self.x-0.5,self.y+1.5,self.x+self.width-1.5,self.y+self.height+0.5,1)
		end,
		on_collide=function(self,dir,other)
			if not other.is_commander or (not other.is_facing_left and dir=="left") or (other.is_facing_left and dir=="right") then
				self:handle_collision_position(dir,other)
				-- bounce!
				if (dir=="left" and self.vx<0) or (dir=="right" and self.vx>0) then
					self.vx*=-1
				elseif (dir=="up" and self.vy<0) or (dir=="down" and self.vy>0) then
					self.vy*=-1
				end
				-- take damage
				if other.is_left_wall then
					commanders[1].health.amount-=10
					freeze_and_shake_screen(0,5)
				elseif other.is_right_wall then
					commanders[2].health.amount-=10
					freeze_and_shake_screen(0,5)
				end
				-- change vertical velocity a bit
				if other.is_commander then
					local offset_y=self.y+self.height/2-self.vy-other.y-other.height/2+other.vy/2
					local max_offset=other.height/2
					local percent_offset=mid(-1,offset_y/max_offset,1)
					local target_vy=1.2*percent_offset+0.6*self.vy
					self.vy=target_vy
					other.gold.amount+=50
					spawn_entity("pop_text",self.x+self.width/2,other.y-5,{
						amount=50,
						type="gold"
					})
					spawn_entity("pop_text",self.x+self.width/2,other.y+1,{
						amount=10,
						type="xp"
					})
				end
				-- stop moving / colliding
				return true
			end
		end
	},
	building={
		width=5,
		height=5,
		upgrades=0,
		offset_y=0,
		draw=function(self)
			pal(3,self.commander.colors[1])
			pal(11,self.commander.colors[3])
			draw_sprite(0+8*self.upgrades,8+15*self.sprite,8,15,self.x-1,self.y-10+self.offset_y)
		end,
		draw_shadow=function(self)
			draw_sprite(24,18+12*self.sprite+4*self.upgrades,11,4,self.x-10,self.y+1)
		end
	},
	keep={
		extends="building",
		sprite=1
	},
	farm={
		extends="building",
		sprite=2,
		offset_y=4
	},
	inn={
		extends="building",
		sprite=3
	}
}

function _init()
	game_frames=0
	freeze_frames=0
	screen_shake_frames=0

	entities={}
	commanders={
		spawn_entity("knight",level_bounds.left.x+6,60,{
			player_num=1,
			facing_dir=1,
			is_facing_left=false
		}),
		spawn_entity("thief",level_bounds.right.x-6-entity_classes.commander.width,60,{
			player_num=2,
			facing_dir=-1,
			is_facing_left=true
		})
	}
	spawn_entity("ball",62,66)
end

-- local skip_frames=0
-- local was_paused=false
function _update(is_paused)
	game_frames=increment_counter(game_frames)
	freeze_frames=decrement_counter(freeze_frames)
	screen_shake_frames=decrement_counter(screen_shake_frames)
	-- skip_frames+=1
	-- if skip_frames%10>0 and not btn(5) then return end
	-- keep track of button presses
	local p
	for p=1,2 do
		local i
		for i=0,5 do
			button_presses[p][i]=btn(i,controllers[p]) and not buttons[p][i]
			buttons[p][i]=btn(i,controllers[p])
		end
	end
	-- update all the entities
	local entity
	for entity in all(entities) do
		if decrement_counter_prop(entity,"frames_to_death") then
			entity:die()
		else
			increment_counter_prop(entity,"frames_alive")
			entity:update()
		end
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
	-- shake the camera
	local shake_x=0
	if freeze_frames<=0 and screen_shake_frames>0 then
		shake_x=ceil(screen_shake_frames/3)*(game_frames%2*2-1)
	end
	-- clear the screen
	camera(shake_x,0)
	cls(0)
	-- draw the level grounds
	-- camera(0,-1)
	rectfill(level_bounds.left.x+0.5,level_bounds.top.y+0.5,level_bounds.right.x-0.5,level_bounds.bottom.y-0.5,3)
	draw_sprite(0,18,4,5,0,31)
	draw_sprite(0,18,4,5,123,31,true)
	draw_sprite(4,18,1,5,4,31,false,false,119)
	draw_sprite(24,15,4,12,0,100)
	draw_sprite(24,15,4,12,123,100,true)
	draw_sprite(28,15,1,12,4,100,false,false,119)
	-- draw castles
	draw_sprite(29,7,29,20,4,11)
	draw_sprite(29,7,29,20,94,11)
	-- draw drawbridges
	draw_sprite(5,18,7,5,14,31)
	draw_sprite(5,18,7,5,104,31)
	-- draw lines
	local y
	for y=37.5,100.5,6 do
		line(63.5,y,63.5,y+2,5)
	end
	pset(63.5,33.5,11)
	pset(63.5,103.5,11)
	-- draw grass
	-- draw_sprite(19,15,2,3,30,92)
	-- draw_sprite(16,15,3,2,40,37)
	-- draw_sprite(16,15,3,2,75,97)
	-- draw_sprite(19,15,4,3,95,42)
	-- draw the entities' shadows
	-- camera()
	local entity
	for entity in all(entities) do
		entity:draw_shadow()
		pal()
	end
	-- draw the entities
	for entity in all(entities) do
		entity:draw()
		pal()
	end
end

-- spawns an entity that's an instance of the given class
function spawn_entity(class_name,x,y,args,skip_init)
	local class_def=entity_classes[class_name]
	local entity
	if class_def.extends then
		entity=spawn_entity(class_def.extends,x,y,args,true)
	else
		-- create a default entity
		entity={
			frames_alive=0,
			frames_to_death=0,
			is_alive=true,
			x=x or 0,
			y=y or 0,
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
			apply_velocity=function(self)
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
						if self:check_for_collisions() then
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
				local stop=false
				-- check for collisions against other entities
				local entity
				for entity in all(entities) do
					if entity!=self then
						local collision_dir=self:check_for_collision(entity)
						if collision_dir then
							-- they are colliding!
							stop=stop or self:on_collide(collision_dir,entity)
						end
					end
				end
				-- check for collisions against the level boundaries
				if band(self.collision_channel,1)>0 then
					if self.y+self.height+self.collision_padding>level_bounds.bottom.y then
						stop=stop or self:on_collide("down",level_bounds.bottom)
					elseif self.x+self.width+self.collision_padding>level_bounds.right.x then
						stop=stop or self:on_collide("right",level_bounds.right)
					elseif self.x-self.collision_padding<level_bounds.left.x then
						stop=stop or self:on_collide("left",level_bounds.left)
					elseif self.y-self.collision_padding<level_bounds.top.y then
						stop=stop or self:on_collide("up",level_bounds.top)
					end
				end
				return stop
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
			draw_shadow=noop,
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
	end
	-- add class-specific properties
	entity.class_name=class_name
	local key,value
	for key,value in pairs(class_def) do
		entity[key]=value
	end
	-- override with passed-in arguments
	for key,value in pairs(args or {}) do
		entity[key]=value
	end
	if not skip_init then
		-- add it to the list of entities
		add(entities,entity)
		-- initialize the entitiy
		entity:init()
	end
	-- return the new entity
	return entity
end

function freeze_and_shake_screen(f,s)
	freeze_frames,screen_shake_frames=max(f,freeze_frames),max(s,screen_shake_frames)
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

-- generates a random integer between min_val and max_val, inclusive
function rnd_int(min_val,max_val)
	return flr(min_val+rnd(1+max_val-min_val))
end

-- wrapper for the sspr function
function draw_sprite(sx,sy,sw,sh,x,y,flip_h,flip_y,sw2,sh2)
	sspr(sx,sy,sw,sh,x+0.5,y+0.5,(sw2 or sw),(sh2 or sh),flip_h,flip_y)
end

__gfx__
00b0b000000000000000001000111011101010100001000000100011000110001000110001111000111100011110001111000115555555555555555555555555
0bbb0bbb0bbb0011110001b1001bb1bb1011b110001b100001b1101b101b100111001b101b11b101b11b101b11b101b11b101b15555555555555555555555555
044404440fbf001bb1001bbb101bb1bb101bbb1001bbb1001bbb1001b1b10001b10001b1b1001b1b1001b1b1001b1b1001b1b105555555555555555555555555
044404440fff1111111111b1111bb1bb101bbb1001bbb101bbbbb1001b10001bbb10001b100001b100001b100001b100001b1005555555555555555555555555
0bbb0bbb0bbb1bb1bb1001b100111b11101bbb1001bbb101bbbbb101b1b10111b11101b1b1001b1b1001b1b1001b1b1001b1b105555555555555555555555555
080c080c080c1111111001b100111111101bbb10011111001bbb101b101b1001b1001b101b11b101b11b101b11b101b11b101b15555555555555555555555555
01111111110200000000011100001110001111100000000011111011000110011100110001111000111100011110001111000115555555555555555555555555
16777777761011100001111111110000001000000000000000000000005555525555555555555555555555555555555555555555555555555555555555555555
17777777771167611117777777771000001000000000000000001000005000525555555555555555555555555555555555555555555555555555555555555555
17777777771177711d67777677761000011100000000000000001000005050525555555555555555555555555555555555555555555555555555555555555555
17777777771177711d777777d6611000011100000000000000011100005000525555555555555555555555555555555555555555555555555555555555555555
17777777771177711d77776711110000111110000000100000011100005555525555555555555555555555555555555555555555555555555555555555555555
17777777771177711d7677d610000000111110000000100000111110002222225555555555555555555555555555555555555555555555555555555555555555
1777777777117771111166d100000001111111000001110000111110005555555555555555555555555555555555555555555555555555555555555555555555
17777777771167610000111000000001111111000001110001111111005555555555555555555555555555555555555555555555555555555555555555555555
1677777776101110b0b000b5b3333011111111100011111001111111005555555555555555555555555555555555555555555555555555555555555555555555
11111111111555551b00b0b5b3333011111111100011111011111111105555555555555555555555555555555555555555555555555555555555555555555555
01111111110508808801b1b5bb333111111111110111111111111111105555555555555555555555555555555555555555555555555555555555555555555555
0222211244428888ee80aa05bbbb3001111111000111111111111111115555555555555555555555555555555555555555555555555555555555555555555555
2bbbb334222488888e8aa7a54bbbb001111111001111111111111111005555555555555555555555555555555555555555555555555555555555555555555555
bbbb311444440888880aa7a544444000111110001111111111111111005555555555555555555555555555555555555555555555555555555555555555555555
bb333114222400888009aaa544444000111110011111111111111110005555555555555555555555555555555555555555555555555555555555555555555555
b3333312444200080000aa0524444000111111111111111111111110005555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000003b00022222000111111111111111111111110005555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000003bb0012222000111111111111111111111110005555555555555555555555555555555555555555555555555555555555555555555555
0000000000000000000100bb11111000111111111211121111111110005555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000001000001111000111111111222221111111110005555555555555555555555555555555555555555555555555555555555555555555555
00000000000600000061600070070707000e0e0ee055555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0000000006ddd6006dd1dd60700757070000e00e0e55555555555555555555555555555555555555555555555555555555555555555555555555555555555555
000600006ddddd606ddddd6077007007705e0e0ee055555555555555555555555555555555555555555555555555555555555555555555555555555555555555
06ddd60066d6d66066d6d66000000000000e0e0e0055555555555555555555555555555555555555555555555555555555555555555555555555555555555555
06d6d600066666006666666000000011111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0666660003bbbb0003bbbb0000000111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
03bbbb000dd666000dd6660000000011111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0666660003bbbb0003bbbb0000000000000555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
06dd6600066666000666660000011111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
06666600066166000661660000111111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0d616d000d616d000d616d0000011111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000000111111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000001111111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000001111111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000000111111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00400000004000000040000000000001111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
64440000644400006444000000000011111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
d4240000d4240000d424000000000001111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
426419a9426419a9426419a900000000111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
2bbb1a9a2bbb1a9a2bbb1a9a00000001111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
666619a9666619a9666619a900000011111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
d6161444d6161444d616144400000001111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000009a909a909a900000000111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0000000000001a9a1a9a1a9a00000001111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000019a919a919a900000011111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000014441444144400000001111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000000000000111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000000000001111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000000000001111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000000000001111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000000000000000000111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000000000004000000000011111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000400000024444000000011111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00040000002444400242422000000011111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00244000024242202227242000000001111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
02424200222724202277724000000111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
22272420227772402717172000000111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
22777240277717202777772000000111111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
27771720233333200333130000000011111555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
033333000bbb1b000bbbbb0055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0b1bbb000b1bbb000b1bbb0055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
88888888888888888888888855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
88888888888888888888888855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0000000000000000000b000055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0000000000000000000b000055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000b0000003bb00055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00000000000b0000003bb00055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0000b000003bb00003bbbb0055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0000b000003bb0000066600055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0003bb0003bbbb00006dd00055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0003bb0000666000006660b055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
003bbbb0006dd0b000dd60b055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
00066600006660b000b663bb55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0006dd0000dd63bb00b66d6055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0006660000666d6003bb6d6055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
000dd60000666d60006d666055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
0006660000d666600066666055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
000d160000d616d000d616d055555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
88888888888888888888888855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
88888888888888888888888855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
88888888888888888888888855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555550153
80000008800000088000000855555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555554567
800000088000000880000008555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555589ab
8888888888888888888888885555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555cdef
