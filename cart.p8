pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

--[[
next steps:
	ball hitting / trigger buildings
	building health

reminders:
	repairing

render layers:
	1:	far background
	2:	background ui elements
	3:	tufts of grass
	4:	troops
	5:	game entities
	6:	effects
	7:	menus
	9:	in-game ui
	10:	ui

hurt channels:
	1:	building
	2:	troops
]]

-- useful no-op function
function noop() end

-- constants
local controllers={1,0}
local level_top=30
local level_bottom=102
local level_left=0
local level_right=127
local bg_color=0
local building_costs={100,150,200}

-- input vars
local buttons
local button_presses

-- entity vars
local entities
local balls
local leaders
local entity_classes={
	-- leaders
	leader={
		width=2,
		height=15,
		-- has_menu_open=false,
		init=function(self)
			local left=self.is_on_left_side
			local props={leader=self}
			-- create sub-entities
			self.army=spawn_entity("army",0,0,props)
			self.real_estate=spawn_entity("real_estate",ternary(left,36,90),39,props)
			-- create ui elements
			self.text_box=spawn_entity("text_box",ternary(left,0,64),104,props)
			self.health=spawn_entity("health_counter",ternary(left,1,74),2,props)
			self.gold=spawn_entity("gold_counter",ternary(left,41,81),10,props)
			self.xp=spawn_entity("xp_counter",ternary(left,35,75),18,props)
			-- create menus
			local menu_x=ternary(left,28,98)
			self.main_menu=spawn_entity("menu",menu_x,66,{
				leader=self,
				items={
					{sprite=6,title="build",description={"construct new","buildings"}},
					{sprite=7,title="upgrade",description={"improve your","buildings"}},
					{sprite=8,title="repair",description={"recover damage","to buildings"}},
					{sprite=9,title="magic",description={"cast great","spells"}}
				},
				on_select=function(self,item)
					local location_menu=self.leader.location_menu
					-- construct a new building
					if item.title=="build" then
						self:hide()
						self.leader.build_menu:show()
					-- upgrade or repair a building
					else
						location_menu.action=item.title
						if location_menu:show() then
							self:hide()
						end
					end
				end
			})
			local build_cost=building_costs[1]
			self.build_menu=spawn_entity("menu",menu_x,66,{
				leader=self,
				items={
					{sprite=1,title="keep",description={"spawns troops"},gold=build_cost},
					{sprite=2,title="farm",description={"generates","gold"},gold=build_cost},
					{sprite=3,title="inn",description={"grants bonus","experience"},gold=build_cost},
					{sprite=4,title="archer",description={"fires arrows","at troops"},gold=build_cost},
					{sprite=5,title="church",description={"heals lost","hit points"},gold=build_cost}
				},
				on_select=function(self,item)
					local leader=self.leader
					-- choose the location to build the building
					if leader.gold.amount>=item.gold then
						local location_menu=leader.location_menu
						location_menu.action="build"
						location_menu.prev_item=item
						if location_menu:show() then
							self:hide()
						end
					-- not enough gold to build
					else
						leader.text_box:warn_gold()
					end
				end
			})
			self.location_menu=spawn_entity("location_menu",menu_x,66,{
				leader=self,
				on_select=function(self,plot)
					local leader=self.leader
					local building=plot.building
					local gold=leader.gold.amount
					if self.action=="build" then
						local cost=building_costs[1]
						if gold>=cost then
							-- deduct the building cost
							leader.gold:decrease(cost)
							-- destroy any existing building in the plot
							if building then
								building:die()
							end
							-- create the new building
							plot.building=spawn_entity(self.prev_item.title,plot.x-3,plot.y-6,{
								leader=leader,
								plot=plot
							})
							-- close the menu
							self:hide()
							leader.text_box:hide()
							leader.has_menu_open=false
						-- not enough gold to build
						else
							leader.text_box:warn_gold()
						end
					elseif self.action=="upgrade" then
						if building and building.upgrades<2 then
							local cost=building_costs[building.upgrades+2]
							if gold>=cost then
								-- deduct the upgrade cost
								leader.gold:decrease(cost)
								building.upgrades+=1
								-- close the menu
								self:hide()
								leader.text_box:hide()
								leader.has_menu_open=false
							-- not enough gold to build
							else
								leader.text_box:warn_gold()
							end
						end
					-- elseif self.action=="repair" then
					-- 	if plot.building then
					-- 	end
					end
				end
			})
		end,
		update=function(self)
			-- open the main menu
			if not self.has_menu_open and btnp2(4,self.player_num,true) then
				self.has_menu_open,self.move_y,self.vy=true,0,0
				self.main_menu:show()
			end
			-- player is paused while a menu is open
			if not self.has_menu_open then
				-- waddle up and down
				self.move_y=ternary(btn2(3,self.player_num),1,0)-ternary(btn2(2,self.player_num),1,0)
				self.vy=self.move_y
				self:apply_velocity()
				-- keep in bounds
				self.y=mid(level_top-self.height/2+1,self.y,level_bottom-self.height/2-2)
			end
		end,
		draw=function(self,x,y)
			-- apply the leaders' colors
			local colors=self.colors
			pal(3,colors[2])
			pal(11,colors[4])
			pal(8,colors[4])
			pal(12,colors[4])
			pal(14,colors[5])
			-- draw the paddle
			sspr2(0,8,2,22,x,y,self.is_facing_left)
			-- waddle animation
			if self.move_y!=0 then
				palt(ternary(self.frames_alive%10<5,12,8),true)
			end
			-- draw the leader
			sspr2(16+4*self.sprite,43,4,6,x+ternary(self.is_facing_left,4,-6),self:center_y()-4,self.is_facing_left)
		end,
		draw_shadow=function(self,x,y)
			rectfill2(self.x-1,self.y+2,self.width,self.height,1)
			rectfill2(self.x+ternary(self.is_facing_left,2,-7),self:center_y(),5,2,1)
		end,
		hit_ball=function(self,ball)
			local x,y=self.x+ternary(self.is_facing_left,5,-3),self:center_y()
			local dx,dy=mid(-100,ball:center_x()-x,100),mid(-100,ball:center_y()-y,100)
			local dist=sqrt(dx*dx+dy*dy)
			ball.leader=self
			-- adjust ball velocity based on line from center of leader to center of ball
			ball.vx=dx/dist
			ball.vy=dy/dist
		end
	},
	witch={
		extends="leader",
		sprite=1,
		colors={5,13,12,12,12,7,4} -- shadow / four midtones / highlight / skin
	},
	thief={
		extends="leader",
		sprite=2,
		colors={4,9,9,10,10,15,4} -- shadow / four midtones / highlight / skin
	},
	knight={
		extends="leader",
		sprite=3,
		colors={2,8,8,8,14,14,15} -- shadow / four midtones / highlight / skin
	},
	-- buildings
	building={
		width=7,
		height=8,
		hurt_channel=1, -- buildings
		upgrades=0,
		shadow_y_offset=3,
		health=100,
		max_health=100,
		show_health_bar_frames=0,
		update=function(self)
			decrement_counter_prop(self,"show_health_bar_frames")
		end,
		draw=function(self,x,y)
			-- apply the leader's colors
			local colors=self.leader.colors
			pal(3,colors[2])
			pal(11,colors[4])
			pal(14,colors[5])
			-- draw the building
			sspr2(95+8*self.upgrades,16*self.sprite-16,8,16,x,y-7)
			-- draw the building's health bar
			if self.show_health_bar_frames>0 then
				local health_bar_y=y+4-self.visible_height[self.upgrades+1]
				rectfill2(x,health_bar_y,7,2,2)
				rectfill2(x,health_bar_y,mid(1,flr(1+6*self.health/self.max_health),7),2,8)
			end
		end,
		draw_shadow=function(self,x,y)
			sspr2(84,12*self.sprite+4*self.upgrades-12,11,4,x-9,y+self.shadow_y_offset)
		end,
		on_hurt=function(self,other)
			if other.last_hit_building!=self then
				other.last_hit_building=self
				-- trigger from a ball with the same leader
				if self.leader==other.leader then
					self:trigger(other)
				-- take damage from a ball from another leader
				elseif other.leader then
					self:damage(other.damage)
				end
			end
		end,
		damage=function(self,amount)
			self.health-=amount
			self.show_health_bar_frames=60
			if self.health<0 then
				self:die()
			end
		end,
		trigger=noop,
		on_death=function(self)
			self.plot.building=nil
		end,
		pop_text=function(self,amount,sprite,color,right_side_icon)
			spawn_entity("pop_text",self:center_x(),self.y+6-self.visible_height[self.upgrades+1],{
				text=""..amount,
				sprite=sprite,
				color=color,
				right_side_icon=right_side_icon
			})
		end
	},
	keep={
		extends="building",
		sprite=1,
		visible_height={9,11,14},
		upgrade_descriptions={{"spawns 3","troops"},{"spawns 7","troops"}},
		trigger=function(self)
			local num_troops=({1,3,7})[self.upgrades+1]
			-- spawn troops
			local i
			for i=1,num_troops do
				self.leader.army:spawn_troop(self,2*i-2)
			end
		end
	},
	farm={
		extends="building",
		shadow_y_offset=1,
		sprite=2,
		visible_height={9,9,9},
		upgrade_descriptions={{"generates","50 gold"},{"generates","75 gold"}},
		trigger=function(self)
			self:pop_text(25,1,10)
		end
	},
	inn={
		extends="building",
		sprite=3,
		visible_height={8,9,10},
		upgrade_descriptions={{"grants 30","experience"},{"grants 50","experience"}},
		trigger=function(self)
			self:pop_text(12,3,14,true)
		end
	},
	archer={
		extends="building",
		sprite=4,
		visible_height={9,11,13},
		upgrade_descriptions={{"wider range"},{"max range"}}
	},
	church={
		extends="building",
		sprite=5,
		visible_height={9,9,12},
		upgrade_descriptions={{"heals 3","hit points"},{"heals 5","hit points"}},
		trigger=function(self)
			self:pop_text(5,0,8)
		end
	},
	-- game entities
	ball={
		width=3,
		height=3,
		vx=1,
		vy=0,
		hit_channel=1+2, -- buildings, troops
		damage=20,
		-- last_hit_building=nil,
		update=function(self)
			local prev_x,prev_y=self.x,self.y
			self:apply_velocity()
			-- bounce off the leaders' paddles
			local leader=leaders[ternary(self.vx<0,1,2)]
			local paddle_x=leader.x+ternary(leader.is_facing_left,-self.width,leader.width)
			if (prev_x<paddle_x)!=(self.x<paddle_x) then
				local percent_velocity_applied=(paddle_x-prev_x)/(self.x-prev_x)
				local collide_y=prev_y+percent_velocity_applied*self.vy
				if collide_y==mid(leader.y-self.height,collide_y,leader.y+leader.height) then
					-- there was a paddle hit!
					self.x,self.y=paddle_x,collide_y
					self.last_hit_building=nil
					leader:hit_ball(self)
				end
			end
			-- bounce off the level walls
			if self.y<level_top then
				self.y=level_top
				if self.vy<0 then
					self.vy*=-1
				end
			elseif self.y>level_bottom-self.height then
				self.y=level_bottom-self.height
				if self.vy>0 then
					self.vy*=-1
				end
			end
			if self.x<level_left then
				self.x=level_left
				if self.vx<0 then
					self.vx*=-1
					self.last_hit_building=nil
				end
			elseif self.x>level_right-self.width then
				self.x=level_right-self.width
				if self.vx>0 then
					self.vx*=-1
					self.last_hit_building=nil
				end
			end
		end,
		draw=function(self,x,y)
			if self.leader then
				pal(7,self.leader.colors[5])
			end
			rectfill2(x,y,self.width,self.height,7)
		end,
		draw_shadow=function(self,x,y)
			rectfill2(x-1,y+1,self.width,self.height,1)
		end
	},
	army={
		width=0,
		height=0,
		render_layer=4,
		init=function(self)
			self.troops={}
		end,
		update=function(self)
			local leader=self.leader
			local is_facing_left=leader.is_facing_left
			-- update all troops
			local troop
			for troop in all(self.troops) do
				decrement_counter_prop(troop,"delay")
				if troop.delay<=0 then
					local speed=troop.speed_mult*0.3
					-- jump
					troop.vz-=0.2
					troop.z+=troop.vz
					if troop.z<=0 then
						troop.z,troop.vz,speed=0,0,troop.speed_mult*0.1
					end
					-- move upwards
					if (is_facing_left and troop.x<=17) or (not is_facing_left and troop.x>=109) then
						troop.y-=speed
						-- destroy the enemy castle
						if troop.y<27 then
							troop:die()
							self.leader.opposing_leader.health:decrease(1)
						end
					-- move sideways
					else
						troop.x+=speed*leader.facing_dir
					end
					-- check for hits
					local entity
					for entity in all(entities) do
						if entity.leader and entity.leader!=self.leader and contains_point(entity,troop.x,troop.y,1) then
							-- check to see if anything is hitting the troop
							if band(entity.hit_channel,2)>0 then -- troops
								troop:die()
							end
							-- check to see if the troop is hitting anything
							if band(1,entity.hurt_channel)>0 then -- buildings
								troop:damage(1)
								entity:damage(1)
							end
						end
					end
				end
			end
		end,
		draw=function(self)
			local colors=self.leader.colors
			local troop
			for troop in all(self.troops) do
				if troop.delay<=0 then
					pset2(troop.x,troop.y-troop.z,colors[4])
					pset2(troop.x,troop.y-troop.z-1,colors[7])
				end
			end
		end,
		draw_shadow=function(self)
			local troop
			for troop in all(self.troops) do
				if troop.delay<=0 then
					pset2(troop.x-1-troop.z,troop.y,1)
				end
			end
		end,
		spawn_troop=function(self,building,delay)
			local army=self
			add(self.troops,{
				x=building:center_x()+rnd(6)-3,
				y=building:center_y()+rnd(5)-2,
				z=0,
				vz=1.8,
				delay=delay,
				health=6,
				speed_mult=0.7+rnd(0.6),
				damage=function(self,damage)
					self.health-=damage
					self.x-=rnd_int(2,3)*army.leader.facing_dir
					if self.health<=0 then
						self:die()
					end
				end,
				die=function(self)
					del(army.troops,self)
				end
			})
		end
	},
	-- ui entities
	menu={
		render_layer=7,
		-- is_visible=false,
		-- highlighted_index=1,
		update=function(self)
			if self.is_visible then
				local player_num=self.leader.player_num
				-- navigate up through the menu items
				if btnp2(2,player_num,true) then
					self:highlight_prev_valid(self.highlighted_index)
				end
				-- navigate down through the menu items
				if btnp2(3,player_num,true) then
					self:highlight_next_valid(self.highlighted_index)
				end
				-- close the menu
				if btnp2(5,player_num,true) then
					self:hide()
					self.leader.text_box:hide()
					self.leader.has_menu_open=false
				-- select the highlighted menu item
				elseif btnp2(4,player_num,true) then
					self:on_select(self:get_highlighted_item())
				end
			end
		end,
		draw=function(self,x,y)
			if self.is_visible then
				local is_facing_left=self.leader.is_facing_left
				local colors=self.leader.colors
				-- draw each menu item
				local menu_y=y-6*#self.items
				local i
				for i=1,#self.items do
					local item_x,item_y=x-7,menu_y+12*i-13
					-- draw the frame
					pal(1,0)
					sspr2(5,41,15,16,item_x,item_y)
					-- apply the leader's colors
					pal()
					pal(3,colors[2])
					pal(12,colors[3])
					pal(11,colors[4])
					pal(14,colors[5])
					-- draw the icon
					sspr2(119,9*self.items[i].sprite-9,9,9,item_x+3,item_y+3)
				end
				-- draw the hand
				pal(1,0)
				pal(11,colors[3])
				sspr2(5,57,13,8,x+ternary(is_facing_left,7,-19),menu_y+12*self.highlighted_index-8,is_facing_left)
			end
		end,
		show=function(self)
			self.is_visible=true
			self:highlight(1)
		end,
		hide=function(self)
			self.is_visible=false
		end,
		highlight_prev_valid=function(self,start_index)
			-- iterate backwards until we find a valid item
			local i
			for i=1,self:num_items() do
				local index=start_index-i
				if index<1 then
					index+=self:num_items()
				end
				if self:is_valid_index(index) then
					self:highlight(index)
					return true
				end
			end
		end,
		highlight_next_valid=function(self,start_index)
			-- iterate fowards until we find a valid item
			local i
			for i=1,self:num_items() do
				local index=start_index+i
				if index>self:num_items() then
					index-=self:num_items()
				end
				if self:is_valid_index(index) then
					self:highlight(index)
					return true
				end
			end
		end,
		highlight=function(self,index)
			self.highlighted_index=index
			-- show a description of the item in the text box
			local item=self:get_highlighted_item()
			local text_box=self.leader.text_box
			text_box:show(item.title,item.description,item.gold)
		end,
		get_item=function(self,index)
			return self.items[index]
		end,
		get_highlighted_item=function(self)
			return self:get_item(self.highlighted_index)
		end,
		is_valid_index=function(self,index)
			return true
		end,
		num_items=function(self)
			return #self.items
		end,
		on_select=noop
	},
	location_menu={
		extends="menu",
		--is_visible=false,
		-- highlighted_index=1,
		draw=function(self,x,y)
			if self.is_visible then
				local is_facing_left=self.leader.is_facing_left
				local plot=self:get_highlighted_item()
				-- draw the hand
				pal(1,0)
				pal(11,self.leader.colors[3])
				sspr2(5,57,13,8,plot.x+ternary(is_facing_left,5,-17),plot.y-4,is_facing_left)
			end
		end,
		show=function(self)
			-- find closest valid index, return true if there's a valid index
			local index=mid(1,flr(self.leader.y/10-1.3),self:num_items())
			if self:is_valid_index(index) then
				self:highlight(index)
				self.is_visible=true
				return true
			elseif self:highlight_next_valid(index) then
				self.is_visible=true
				return true
			end
		end,
		hide=function(self)
			self.is_visible=false
		end,
		highlight=function(self,index)
			self.highlighted_index=index
			local plot=self:get_highlighted_item()
			local building=plot.building
			if building then
				-- show upgrade text
				if self.action=="upgrade" then
					local cost=building_costs[building.upgrades+2]
					self.leader.text_box:show("upgrade",building.upgrade_descriptions[building.upgrades+1],cost)
				end
				-- show repair text
				if self.action=="repair" then
					self.leader.text_box:show("repair",{"120 / 150","hit points"},30)
				end
			end
		end,
		num_items=function(self)
			return 7
		end,
		get_item=function(self,index)
			return self.leader.real_estate.plots[index]
		end,
		is_valid_index=function(self,index)
			local building=self:get_item(index).building
			return self.action=="build" or (building and (self.action!="upgrade" or building.upgrades<2))
		end
	},
	real_estate={
		render_layer=3,
		init=function(self)
			-- create plots
			local x,y=self.x,self.y
			self.plots={}
			local i
			for i=0,6 do
				add(self.plots,{
					x=x,
					y=y,
					tuft=rnd_int(1,3)
				})
				x-=({13,-26,13})[i%3+1]
				y+=({12,4,12})[i%3+1]
			end
		end,
		draw=function(self)
			-- draw tufts of grass
			local plot
			for plot in all(self.plots) do
				if not plot.building then
					sspr2(1+4*plot.tuft,38,4,3,plot.x-2,plot.y-2)
				end
			end
		end
	},
	counter={
		render_layer=2,
		min_tick=1,
		max_tick=1,
		-- last_change=nil,
		frames_since_change=9999,
		update=function(self)
			increment_counter_prop(self,"frames_since_change")
			local change=rnd_int(self.min_tick,self.max_tick)
			if self.delayed_amount<self.amount then
				self.delayed_amount=min(self.amount,self.delayed_amount+change)
			elseif self.delayed_amount>self.amount then
				self.delayed_amount=max(self.amount,self.delayed_amount-change)
			end
		end,
		increase=function(self,amount)
			self.amount=max(0,self.amount+amount)
			if self.max_amount and self.amount>self.max_amount then
				self.amount=self.max_amount
			end
			self.last_change=ternary(self.amount>0,"increase","decrease")
			self.frames_since_change=0
			self:on_change(amount)
		end,
		decrease=function(self,amount)
			self:increase(-amount)
		end,
		on_change=noop
	},
	health_counter={
		extends="counter",
		amount=42,
		delayed_amount=42,
		max_amount=42,
		draw=function(self,x,y)
			local amount,left=self.delayed_amount,self.leader.is_on_left_side
			-- draw heart
			spr2(0,x+ternary(left,0,43),y-3)
			-- draw purple bar
			local bar_left=x+ternary(left,10,0)
			local fill_left=bar_left+ternary(left,0,42-amount)
			rectfill2(bar_left,y,42,4,2)
			-- draw red fill
			if amount>0 then
				rectfill2(fill_left,y,amount,4,8)
				if amount>9 then
					sspr2(0,63,5,1,fill_left+amount-7,y+1)
				end
			end
			-- round off the bar
			-- todo: cut tokens here if necessary (just do bg_color)
			pset2(bar_left,y,ternary(amount>ternary(left,1,41),2,bg_color))
			pset2(bar_left,y+3)
			pset2(bar_left+41,y,ternary(amount>ternary(left,41,1),2,bg_color))
			pset2(bar_left+41,y+3)
		end
	},
	gold_counter={
		extends="counter",
		amount=900,
		delayed_amount=900,
		min_tick=7,
		max_tick=12,
		max_amount=999,
		draw=function(self,x,y)
			-- draw coin
			spr2(1,x-10,y-2)
			-- draw gold amount
			if self.delayed_amount>self.amount then
				color(8)
			elseif self.delayed_amount<self.amount then
				color(7)
			else
				color(10)
			end
			print2(self.delayed_amount,x,y)
		end
	},
	xp_counter={
		extends="counter",
		amount=50,
		delayed_amount=0,
		max_amount=100,
		level=9,
		draw=function(self,x,y)
			-- draw level
			sspr2(17,38,11,3,x,y+1)
			print2(self.level,x+14,y,14)
			-- draw xp bar
			rectfill2(x,y+6,17,2,2)
			-- draw xp fill
			if self.delayed_amount>0 then
				rectfill2(x,y+6,mid(1,flr(1+16*self.delayed_amount/self.max_amount),17),2,14)
			end
		end
	},
	mana_counter={
		extends="counter"
	},
	text_box={
		render_layer=9,
		-- is_visible=false,
		-- title=nil,
		-- description=nil,
		-- gold=nil,
		gold_warning_frames=0,
		update=function(self)
			decrement_counter_prop(self,"gold_warning_frames")
		end,
		draw=function(self,x,y)
			if self.is_visible then
				-- draw pane
				pal(11,self.leader.colors[3])
				rectfill2(x+5,y,53,23,7)
				sspr2(0,40,5,23,x,y)
				sspr2(0,40,5,23,x+58,y,true)
				pal()
				-- draw title and gold cost
				if self.gold then
					print2(self.title,x+7,y+2,0)
					if self.gold_warning_frames%8>4 then
						pal(9,8)
					end
					spr(2,x+35,y)
					print2(self.gold,x+45,y+2,9)
				-- draw title centered
				else
					print2_center(self.title,x+32,y+2,0)
				end
				local description=self.description
				if description then
					-- draw two-line description
					if #description>1 then
						print2_center(description[1],x+32,y+10,5)
						print2_center(description[2],x+32,y+16)
					-- draw one-line description
					else
						print2_center(description[1],x+32,y+12,5)
					end
				end
			end
		end,
		show=function(self,title,description,gold)
			self.is_visible,self.gold_warning_frames=true,0
			self.title,self.description,self.gold=title,description,gold
		end,
		hide=function(self)
			self.is_visible,self.gold_warning_frames=false,0
		end,
		warn_gold=function(self)
			self.gold_warning_frames=32
		end
	},
	level_up_notification={},
	-- effects
	pop_text={
		render_layer=6,
		frames_to_death=34,
		vy=-1.2,
		update=function(self)
			self.vy+=0.07
			self:apply_velocity()
		end,
		draw=function(self,x,y)
			local sprite_width=fget(self.sprite)
			local width=sprite_width+2+4*#self.text
			-- draw the sprite
			spr2(self.sprite,x+sprite_width-9-flr(width/2)+ternary(self.right_side_icon,4*#self.text+1,0),y-6)
			-- draw the text
			print2(self.text,x+ternary(self.right_side_icon,-1,sprite_width+1)-flr(width/2),y-4,self.color)
		end
	},
	-- background entities
	castle={
		render_layer=1,
		draw=function(self,x,y)
			sspr2(0,98,27,30,x,y)
		end
	}
}

function _init()
	buttons={{},{}}
	button_presses={{},{}}
	entities={}
	balls={}
	-- spawn entities
	spawn_entity("castle",4,8)
	spawn_entity("castle",96,8)
	leaders={
		spawn_entity("witch",6,59,{
			player_num=1,
			facing_dir=1,
			is_on_left_side=true
		}),
		spawn_entity("thief",119,59,{
			player_num=2,
			facing_dir=-1,
			is_facing_left=true
		})
	}
	leaders[1].opposing_leader=leaders[2]
	leaders[2].opposing_leader=leaders[1]
	add(balls,spawn_entity("ball",62,65))
end

function _update()
	-- keep track of button presses
	local p
	for p=1,2 do
		local i
		for i=0,5 do
			button_presses[p][i]=btn(i,controllers[p]) and not buttons[p][i]
			buttons[p][i]=btn(i,controllers[p])
		end
	end
	-- update all of the entities
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
	-- check for troop fights
	local troop
	for troop in all(leaders[1].army.troops) do
		local troop2
		for troop2 in all(leaders[2].army.troops) do
			if troop.x>troop2.x-1 and troop.y==mid(troop2.y-4,troop.y,troop2.y+4) and troop.health>0 and troop2.health>0 then
				troop:damage(1)
				troop2:damage(1)
			end
		end
	end
	-- remove dead entities
	for entity in all(entities) do
		if not entity.is_alive then
			del(entities,entity)
		end
	end
	-- sort entities for rendering
	sort_list(entities,is_rendered_on_top_of)
end

function _draw()
	-- clear the screen
	cls(bg_color)
	-- outline the screen's bounding box
	rect(0.5,0.5,126.5,127.5,1)
	-- draw the floating island
	map()
	-- draw all of the entities' shadows
	local entity
	for entity in all(entities) do
		entity:draw_shadow(entity.x,entity.y)
		pal()
	end
	-- draw all of the entities
	for entity in all(entities) do
		entity:draw(entity.x,entity.y)
		pal()
	end
end

-- spawns an instance of the given class
function spawn_entity(class_name,x,y,args,skip_init)
	local class_def=entity_classes[class_name]
	local entity
	if class_def.extends then
		entity=spawn_entity(class_def.extends,x,y,args,true)
	else
		-- create a default entity
		entity={
			-- life cycle vars
			is_alive=true,
			frames_alive=0,
			frames_to_death=0,
			-- position vars
			x=x or 0,
			y=y or 0,
			vx=0,
			vy=0,
			width=8,
			height=8,
			-- hit detection vars
			hit_channel=0,
			hurt_channel=0,
			-- render vars
			render_layer=5,
			-- functions
			init=noop,
			update=function(self)
				self:apply_velocity()
			end,
			apply_velocity=function(self)
				self.x+=self.vx
				self.y+=self.vy
			end,
			center_x=function(self)
				return self.x+self.width/2
			end,
			center_y=function(self)
				return self.y+self.height/2
			end,
			-- hit functions
			is_hitting=function(self,other)
				return band(self.hit_channel,other.hurt_channel)>0 and objects_overlapping(self,other)
			end,
			on_hit=noop,
			on_hurt=noop,
			-- draw functions
			draw=function(self)
				self:draw_outline()
			end,
			draw_shadow=noop,
			draw_outline=function(self,color)
				rect(self.x+0.5,self.y+0.5,self.x+self.width-0.5,self.y+self.height-0.5,color or 7)
			end,
			-- life cycle functions
			die=function(self)
				if self.is_alive then
					self.is_alive=false
					self:on_death()
				end
			end,
			despawn=function(self)
				self.is_alive=false
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

function btn2(button_num,player_num)
	return buttons[player_num][button_num]
end

function btnp2(button_num,player_num,consume_press)
	if button_presses[player_num][button_num] then
		if consume_press then
			button_presses[player_num][button_num]=false
		end
		return true
	end
end

-- bubble sorts a list
function sort_list(list,func)
	local i
	for i=1,#list do
		local j=i
		while j>1 and func(list[j-1],list[j]) do
			list[j],list[j-1]=list[j-1],list[j]
			j-=1
		end
	end
end

-- returns true if a is rendered on top of b
function is_rendered_on_top_of(a,b)
	return ternary(a.render_layer==b.render_layer,a:center_y()>b:center_y(),a.render_layer>b.render_layer)
end

-- check to see if two rectangles are overlapping
function rects_overlapping(x1,y1,w1,h1,x2,y2,w2,h2)
	return x1<x2+w2 and x2<x1+w1 and y1<y2+h2 and y2<y1+h1
end

-- check to see if obj1 and obj2 are overlapping
function objects_overlapping(obj1,obj2)
	return rects_overlapping(obj1.x,obj1.y,obj1.width,obj1.height,obj2.x,obj2.y,obj2.width,obj2.height)
end

-- checks to see if a point is contained within obj's bounding box
function contains_point(obj,x,y,fudge)
	fudge=fudge or 0
	return obj.x-fudge<x and x<obj.x+obj.width+fudge and obj.y-fudge<y and y<obj.y+obj.height+fudge
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

-- wrappers for drawing functions
function pset2(x,y,...)
	pset(x+0.5,y+0.5,...)
end

function print2(text,x,y,...)
	print(text,x+0.5,y+0.5,...)
end

function print2_center(text,x,y,...)
	print(text,x-2*#(""..text)+0.5,y+0.5,...)
end

function spr2(sprite,x,y,...)
	spr(sprite,x+0.5,y+0.5,1,1,...)
end

function sspr2(sx,sy,sw,sh,x,y,flip_h,flip_y,sw2,sh2)
	sspr(sx,sy,sw,sh,x+0.5,y+0.5,(sw2 or sw),(sh2 or sh),flip_h,flip_y)
end

function rectfill2(x,y,width,height,...)
	rectfill(x+0.5,y+0.5,x+width-0.5,y+height-0.5,...)
end

__gfx__
0000000000000000000000000000000000000000000000000000000000000000000000000000000055550000000000000000000000000000003b000000060000
0000000000000000000000000000000000000000000000000000000000000000000000000000000055550000011111100000000000000000003bb00006ddd600
0088088000000aa000000990000000000000ccc700000000000000000000000000000000000000005555000011111110000000000000000000100bb006d6d600
08888ee80000aa7a0000999900e0e0ee000ccc700000000000000000000000000000000000000000555500000111111000000000006000000616000006666600
088888e80000aaaa00009999000e00ee0000cccc00000000000000000000000000000000000000005555000000000000000000006ddd6006dd1dd60003bbbe00
0088888000009aaa0000999900e0e0e000000cc00222222222222b22222222222222222222222200555500111111111000600006ddddd606ddddd60006666600
00088800000009a000000990000000000000c0002bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb2055550111111111106ddd60066d6d66066d6d660006dd6600
0000800000000000000000000000000000000000bbb3333333331b333333333b333333333333bbb055550011111111106d6d6000666660066666660006666600
3e3e0000000cc000000005555555555555555555b333b333555555555555555555555555333333b05555011111111110666660003bbbe0003bbbe0000d616d00
3e3e0000000cc000000005555555555555555555b3b1b3335555555555555555555555553333b3b055551111111111103bbbe000dd666000dd66600000000000
3e3e0000000cc00000000555555555555555555531b333335555555555555555555555553331b3305555111111111110666660003bbbe0003bbbe00000400000
3e3e0000000ccc00000005555555555555555555333333335555555555555555555555553333333055550111111111106dd66000666660006666600064440000
3e3e00000000cc0000000555555555555555555533333333555555555555555555555555333333305555000000111110666660006616600066166000d4240000
3e3e000000000cc000000555555555555555555533333333555555555555555555555555333333305555000001111110d616d000d616d000d616d000426409a9
3e3e00000000ccc0000005555555555555555555333333335555555555555555555555553333333055550000001111100000000000000000000000002bbb1a9a
3e3e00000000c0cc00000555555555555555555533333333555555555555555555555555333333305555000000011110000000000000000000000000666619a9
3e3e0000000cc00c00000555555555555555555533333333555555553333333300001000333333305555000000111110000000000000000000000000d6161444
3e3e0000000c000cc000055555555555555555553333333355555555333333350001000033333330555500000111111000000000000000000000000000000000
3e3e000000cc000c0ccc055555555555555555553333333355555555333333350000000033333330555500000011111000000000000000000000000000040000
3e3e00000c0000c00000c55555555555555555553333333355555555333333330000000033333330555500000001111000000000000000000000000000244000
3e3e00000c0000c00000055555555555555555553333333355555555333333330000000033333330555500000011111000000000000000000000000002424200
3e3e000cc0c000cc0000055555555555555555553333333355555555333333350000000033333330555500000111111004000000040000000400000022272420
3e3e00cc0000000c0000055555555555555555553333333355555555333333350000000033333330555500000011111644400006444000064440000022777240
333e0cc0c0000000c000055555555555555555553333333355555555333333330000000033333330555500000001111d4240000d4240000d4240000027771720
003ec00000000000cc00055555555555555555553333333333333333333333330010000033333330555500000011111426409a9426409a9426409a9003333300
003e0000000000000cc00555555555555555555533333333333333333333333500010000333333305555000000111112bbb1a9a2bbb1a9a2bbb1a9a00e1eee00
003e0000000000000c0c05555555555555555555333b333333333333333333350010100033333330555500000011111666619a9666619a9666619a9000000000
003e000000000000c000c5555555555555555555b31b333333333333333333330010000033b333b0555500000001111d6161444d6161444d6161444000333300
003e00000000000c000005555555555555555555b333333333333333333333330000000031b333b055550000011111100000000000009a909a909a9000eeee00
00330000000000c0c00005555555555555555555bbb33333333333333333333b000000003333bbb05555000001111110000000000001a9a1a9a1a9a000333300
55555555555555555555555555555555555555554bbbbbbbbbbbbbbbbbbbbbbb00000000bbbbbb4055550000011111100000000000019a919a919a9000420400
55555555555555555555555555555555555555554444444444444444444444440000000044444440555500000011111000000000000144414441444000422400
55555555555555555555555555555555555555554444444444444444444444444444444444444440555500001111111000000000000000000000000000444400
55555555555555555555555555555555555555552444444444444444444444444444444444444420555500001111111000000000000000000000000000444400
55555555555555555555555555555555555555552222224444444444444422222222222244222220555500001111111000000000000000000000000000420400
55555555555555555555555555555555555555551222222222222222222222222222222222222210555500000111111000000000000000000000000000400400
55555555555555555555555555555555555555551111222222222222222222222222222222211110555500000000000000000000000000000040000000ddd000
5555555555555555555555555555555555555555011111112222222222222222222222221111110055550000011111100000000000400000024444000dd6dd00
55555000b00000000e00e0e0e000555555555555000111111111111111111111111111111111000055550000011110000040000002444400242422000dd6dd00
555550b0b0b0b00b0e00e2e0e000555555555555000000111111111111111111111111111000000055550000011111100244000024242202227242000d666d00
0ffff1b1b01b001b0ee00e00ee0255555555555555555555555555555555555555555555555555555555000000000000242420022272420227772400066b6600
0ff77000000000000000555555555555555555555555555555555555555555555555555555555555555500011111111222724202277724027171720006bbb600
bbbbb0011111111111005555555555555555555555555555555555555555555555555555555555555555000111111002277724027771720277777200066bdd00
bbbb701f777777777f1000b0b0000000555555555555555555555555555555555555555555555555555500011111111277717202333332003331300006666600
bbb770177777777777100bbb0bbb0bbb555555555555555555555555555555555555555555555555555500000000000033333000eee1e000eeeee00006616600
bbbb7017777777777710044404440fbf5555555555555555555555555555555555555555555555555555011111111110e1eee000e1eee000e1eee00000000000
bbbbb017777777777710044404440fff555555555555555555555555555555555555555555555555555501111111100000000000000000000000000040000000
077770177777777777100bbb0bbb0bbb555555555555555555555555555555555555555555555555555501111111111000000000000000000000000044400000
07777017777777777710080c080c080c555555555555555555555555555555555555555555555555555500000000000000000000000000000000000040400040
07777017777777777710555555555555555555555555555555555555555555555555555555555555555500000011111000000000000000003333330040400040
0777701777777777771055555555555555555555555555555555555555555555555555555555555555550000011111100000000000000000eeeeee0044440c40
0777701f77777777771055555555555555555555555555555555555555555555555555555555555555550000111111100000000003333000333333004040ccc0
0777701f7777777777105555555555555555555555555555555555555555555555555555555555555555000001111110000000000eeee0004200040040cccdd0
0777701ff77777777f100003bb003bb3bbbb3bb003bb03bb005555555555555555555555555555555555000011111110033330000333300042222400ccddccc0
077770111111111111100003bb003bb03bb03bbb03bb03bb0055555555555555555555555555555555550000111111100eeee0000420400044444400000c0000
077770011111111111000003bb003bb03bb03bb3b3bb03bb00555555555555555555555555555555555500111111111003333000042240000422400000ccc000
077770000000000000000003bb3b3bb03bb03bb3b3bb03bb0055555555555555555555555555555555550000111111100420400004444000044440000ccccc00
077770001111111110550003bbbbbbb03bb03bb03bbb0000005555555555555555555555555555555555000011111110042240000422400004224000ccccccc0
0777711177777777715500003bb3bb03bbbb3bb003bb03bb00555555555555555555555555555555555500111111111004444000044440000444400000ccc000
0f7771bf7777f777f1553bb00003bbbb003bbbb03bbbbb03bb555555555555555555555555555555555501111111111004444000044440000420400000ccc000
0f7771b777777bff11553bb0003bb03bb3bb03bb3bb00003bb555555555555555555555555555555555555555555555004204000042040000400400000ccc000
0ff771b7777f711110553bb0003bb03bb3bbbb003bb00003bb555555555555555555555555555555555555555555555004004000040040000400400000ccc0c0
0ffff1b7f77bf10000553bb0003bb03bb003bbbb3bbb0003bb5555555555555555555555555555555555555555555550000000000000000000000000000ccc00
e0eee1111ffb100000553bb0003bbb3bb3bb03bb3bb0000000555555555555555555555555555555555555555555555000000000000000000000000000005d00
555550001111000000553bbbbb03bbbb003bbbb03bbbbb03bb55555555555555555555555555555555555555555555500000000000000000000000000005d000
3bb0003bbbbb3bb03bb3bbbbb3bb0000003bb03bb3bbbbb55555555555555555555555555555555555555555555555500000000000000000000000000005d00d
3bb0003bb0003bb03bb3bb0003bb0000003bb03bb3bb3bb55555555555555555555555555555555555555555555555500000000000000000006000000005dddd
3bb0003bb0003bb03bb3bb0003bb0000003bb03bb3bb3bb555555555555555555555555555555555555555555555555000000000000000000060000000c55dd0
3bb0003bbb003bbb3bb3bbb003bb0000003bb03bb3bbbbb5555555555555555555555555555555555555555555555550000000000000000006d600000ccc0000
3bb0003bb00003bbbb03bb0003bb0000003bbb3bb3bb00055555555555555555555555555555555555555555555555500ddd00000ddd0000d666d00555c00000
3bbbbb3bbbbb003bb003bbbbb3bbbbb00003bbbb03bb0005555555555555555555555555555555555555555555555550dd6dd000dd6dd00dd666dd050d000000
0003bb003bb3bbbb3bbbbbb3bbbb03bb03bb000055555555555555555555555555555555555555555555555555555550dd6dd00ddd6ddd06d666d6055d000000
0003bb003bb03bb0003bb03bb03bb3bb03bb000055555555555555555555555555555555555555555555555555555550d666d00dd666dd0666b6660999909999
0003bb003bb03bb0003bb03bb00003bb03bb00005555555555555555555555555555555555555555555555555555555066b6600d66b66d066bbb6609fff9fff9
0003bb3b3bb03bb0003bb03bb00003bbbbbb0000555555555555555555555555555555555555555555555555555555506bbb60066bbb660666b6dd09fff9fff9
0003bbbbbbb03bb0003bb03bbb3bb3bb03bb00005555555555555555555555555555555555555555555555555555555066bdd00666b6660666666609fff9fff9
00003bb3bb03bbbb003bb003bbbb03bb03bb0000555555555555555555555555555555555555555555555555555555506666600dd666660dd6666609fff9fff9
00003bbbbbb3bb03bb3bbbb3bbbbb3bbbbb0000055555555555555555555555555555555555555555555555555555550661660066616660666166609fff9fff9
0000003bb003bb03bb03bb03bb0003bb000000005555555555555555555555555555555555555555555555555555555000000000000000000000000c99f9f99c
0000003bb003bb03bb03bb03bb0003bb000000005555555555555555555555555555555555555555555555555555555000000000000000000000000cccc3cccc
0000003bb003bbbbbb03bb03bbb003bbbb0000005555555555555555555555555555555555555555555555555555555555555555555555555555555000ccc000
0000003bb003bb03bb03bb03bb0003bb000000005555555555555555555555555555555555555555555555555555555555555555555555555555555000020000
0000003bb003bb03bb3bbbb3bbbbb3bb000000005555555555555555555555555555555555555555555555555555555555555555555555555555555000880000
3bb3bb3bb003bb3bbbb03bbbb03bb03bb3bbbbbb5555555555555555555555555555555555555555555555555555555555555555555555555555555008800080
3bb3bb3bbb03bb03bb03bb03bb3bb03bb003bb005555555555555555555555555555555555555555555555555555555555555555555555555555555008a88880
3bbbb03bb3b3bb03bb03bb00003bb03bb003bb0055555555555555555555555555555555555555555555555555555555555555555555555555555550089aa998
3bbbbb3bb3b3bb03bb03bb3bbb3bbbbbb003bb00555555555555555555555555555555555555555555555555555555555555555555555555555555500899aaa9
3bb3bb3bb03bbb03bb03bbb3bb3bb03bb003bb0055555555555555555555555555555555555555555555555555555555555555555555555555555550089aaaa9
3bb3bb3bb003bb3bbbb03bbbb03bb03bb003bb00555555555555555555555555555555555555555555555555555555555555555555555555555555500089aaa9
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555080089990
057777770577777770577777770057777770577777770057777770577755555555555555555555555555555555555555555555555555555555555550030d0000
57770577757770577757770577757770577757770577757770577757775555555555555555555555555555555555555555555555555555555555555000ddd030
5777057775777057775777057775777057775777057775777057770000555555555555555555555555555555555555555555555555555555555555500c22cbb0
57770577757770000057770577757770577757770577757770577757775555555555555555555555555555555555555555555555555555555555555044aa3bb0
577705777577700000577705777577705777577705777577705777577755555555555555555555555555555555555555555555555555555555555550089aabb0
5777057775777000005777777705777057775777057770577777775777555555555555555555555555555555555555555555555555555555555555508889a990
56665666656660000056660000056660566656660566600000566656665555555555555555555555555555555555555555555555555555555555555228eea994
05666656656660000056660000005666666056660566605666666056665555555555555555555555555555555555555555555555555555555555555244eec444
00000000000001000000000000000000000000001000000000000000000000000001000000000000000000000000001000000000000055555555555022444440
0000000000000100000000000000000000000000100000000000000000000000000100000000000000000000000000100000000000005555555555500cc6c000
0000000000001150000000000000000000000001150000000000000000000000001150000000000000000000000001150000000000005555555555500ccc0000
0000000000001150000000000000000000000001150000000000000000000000001150000000000000000000000001150000000000005555555555500cc0000c
000000000001111500000000000000000000001111500000000000000000000001111500000000000000000000001111500000000000555555555550ccc00ccc
000000000001111500000000000000000000001111500000000000000000000001111500000000000000000000001111500000000000555555555550cc0cccc0
101010000011111550000010505101010000011111550000010505101010000011111550000010505101010000011111550000010505555555555550ccc00cc0
111110000011111550000015555111110000011111550000015555111110000011111550000015555111110000011111550000015555555555555550c000cc00
1111500001111155550000111551111500001111155550000111551111500001111155550000111551111500001111155550000111555555555555500000c000
111150000001111100000011115111150000001111100000011115111150000001111100000011115111150000001111100000011115555555555550000c0000
11115000000111150010001111511115000000111150010001111511115000000111150010001111511115000000111150010001111555555555555555555555
11111000100111150115001111511111000100111150115001111511111000100111150115001111511111000100111150115001111555555555555555555555
11111001110111151111501111511111001110111151111501111511111001110111151111501111511111001110111151111501111555555555555555555555
11111111111111151115555111511111111111111151115555111511111111111111151115555111511111111111111151115555111555555555555555555555
11111111111111111111111111511111111111111111111111111511111111111111111111111111511111111111111111111111111555555555555555555555
11111111111111511111111111511111111111111511111111111511111111111111511111111111511111111111111511111111111555555555555555555555
11111111111111151111111111511111111111111151111111111511111111111111151111111111511111111111111151111111111555555555555555555555
11111111111111151111111111511111111111111151111111111511111111111111151111111111511111111111111151111111111555555555555555555555
11111111111111111111111111511111111111111111111111111511111111111111111111111111511111111111111111111111111555555555555555555555
11111111111211121111111111111111111111211121111111111111111111111211121111111111111111111111211121111111111155555555555555555555
11111111111222221111111111111111111111222221111111111111111111111222221111111111111111111111222221111111111155555555555555555555
00000000011244420000000000000000000011244420000000000000000000011244420000000000000000000011244420000000000055555555555555555555
00000000033422240000000000000000000033422240000000000000000000033422240000000000000000000033422240000000000055555555555555555555
00000000011444440000000000000000000011444440000000000000000000011444440000000000000000000011444440000000000055555555555555555555
00000000011422240000000000000000000011422240000000000000000000011422240000000000000000000011422240000000000055555555555555555555
00000000001244420000000000000000000001244420000000000000000000001244420000000000000000000001244420000000000055555555555555555555
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000055555555555555550123
00000000000044400000000000000000000000044400000000000000000000000044400000000000000000000000044400000000000055555555555555554567
000000000004444400000000000000000000004444400000000000000000000004444400000000000000000000004444400000000000555555555555555589ab
0000000000004440000000000000000000000004440000000000000000000000004440000000000000000000000004440000000000005555555555555555cdef
__gff__
0704040605000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0508080808080607080808080808080900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1525252525252527252525252525251900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2525252525252527252525252525252900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2525252525252527252525252525252900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2525252525252527252525252525252900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2525252525252527252525252525252900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2525252525252527252525252525252900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2525252525252527252525252525252900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2525252525252527252525252525252900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3536363636363637363636363636363900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4547484847464746474648474847484900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000028000000000000000000380000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
