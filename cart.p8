pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

--[[
next steps:
	level up rewards
	effect when building is damaged
	effect when building is destroyed
	effect when building is triggered
	effect when building is repaired
	repairing buildings
	game ends
	game starts
	edges of paddle hit sharper
	moving your paddle imparts momentum
	consider adding druid

title screen:
	arpongi
	2-player competitive
	created by bridgs
	(bridgs_dev)
	music by x & x
	press any button to continue

character select:
	choose your characters
	select1 / select 2

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
local leader_constants={
	{
		name="witch",
		colors={5,13,12,12,12,7,4},
		description={"cast powerful","spells"}
	},
	{
		name="thief",
		colors={4,9,9,10,10,15,4},
		description={"fire deadly","trickshots"}
	},
	{
		name="knight",
		colors={2,8,8,8,14,14,15},
		description={"command","loyal troops"}
	},
	{
		name="druid",
		colors={5,3,3,11,11,7,9},
		description={"abcdefghijk","abcdefghijk"}
	}
}
local fill_wipe={
	0b1111110111111111.1,
	0b1010110110101111.1,
	0b1010010110100101.1,
	0b1010010010100000.1,
	0b0000010000000000.1
}

-- effect vars
local game_frames=0
local freeze_frames=0
local screen_shake_frames=0

-- input vars
local buttons
local button_presses

-- entity vars
local entities
local balls
local leaders
local real_estates
local entity_classes={
	-- leaders
	leader={
		is_freeze_frame_immune=true,
		width=2,
		height=15,
		-- has_menu_open=false,
		init=function(self)
			local left=self.is_on_left_side
			local props={leader=self}
			-- create sub-entities
			self.castle=spawn_entity("castle",ternary(left,4,96),8,props)
			self.army=spawn_entity("army",0,0,props)
			self.real_estate=real_estates[self.player_num]
			-- create ui elements
			self.text_box=spawn_entity("text_box",ternary(left,0,64),104,props)
			self.health=spawn_entity("health_counter",ternary(left,1,71),2,props)
			self.gold=spawn_entity("gold_counter",ternary(left,44,78),10,props)
			self.xp=spawn_entity("xp_counter",ternary(left,38,72),18,props)
			self.level_up_notification=spawn_entity("level_up_notification",ternary(left,8,72),7,props)
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
							building=spawn_entity(self.prev_item.title,plot.x-3,plot.y-6,{
								leader=leader,
								plot=plot
							})
							plot.building=building
							spawn_entity("poof",plot.x-6,plot.y-8)
							spawn_entity("building_halo",building.x-2,building.y-building.visible_height[1+building.upgrades]+2)
							-- close the menu
							self:hide()
							leader.text_box:hide()
							leader.has_menu_open=false
						-- not enough gold to build
						else
							leader.text_box:warn_gold()
						end
					elseif self.action=="upgrade" then
						if building then
							local cost=building_costs[building.upgrades+2]
							local required_level=ternary(building.upgrades==0,3,6)
							-- no further upgrades / not high enough level to upgrade
							if building.upgrades>=2 or self.leader.xp.level<required_level then
								leader.text_box:warn_description()
							elseif gold>=cost then
								-- deduct the upgrade cost
								leader.gold:decrease(cost)
								building.upgrades+=1
								building.max_health+=75
								building.health+=75
								spawn_entity("poof",plot.x-6,plot.y-8)
								spawn_entity("building_halo",building.x-2,building.y-building.visible_height[1+building.upgrades]+2)
								-- close the menu
								self:hide()
								leader.text_box:hide()
								leader.has_menu_open=false
							-- not enough gold to upgrade
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
			if freeze_frames>0 then
				self.frames_alive-=1
			elseif not self.has_menu_open then
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
			sspr2(14+5*self.sprite,47,5,6,x+ternary(self.is_facing_left,3,-6),self:center_y()-4,self.is_facing_left)
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
			-- gain gold and xp
			local pop_x=self.x+ternary(self.is_on_left_side,4,1)
			local y=self.y
			if self.xp.level<9 then
				self.xp:increase(15)
				spawn_entity("pop_text",pop_x,y,{
					text="15",
					sprite=3,
					color=14,
					right_side_icon=true
				})
				y-=6
			end
			self.gold:increase(40)
			spawn_entity("pop_text",pop_x,y,{
				text="40",
				sprite=1,
				color=10
			})
		end,
		level_up=function(self)
		end
	},
	witch={
		extends="leader",
		sprite=1,
		-- colors={5,13,12,12,12,7,4}, -- shadow / four midtones / highlight / skin
		level_up=function(self,level)
			-- new spell - fireball
			-- new spell - plenty
			-- new spell - bolt
			-- mana regen per inn
			-- archers shoot fireballs
			-- triple mana regen

			-- juicy gameplan: nonstop spellcasting

			-- game plan: regen mana, cast spells
			-- level 2: 
			-- level 3: lvl 2 buildings unlocked
			-- level 4: 
			-- level 5: 
			-- level 6: lvl 3 buildings unlocked 
			-- level 7: 
			-- level 8: 
			-- level 9: 
		end
	},
	thief={
		extends="leader",
		sprite=2,
		-- colors={4,9,9,10,10,15,4}, -- shadow / four midtones / highlight / skin
		level_up=function(self,level)
			-- +move speed / +ball speed
			-- bonus per farm
			-- bonus per archers
			-- shoot arrows
			-- double trigger
			-- steal gold
			-- shadow ball

			-- juicy gameplay: fill board with multiballs

			-- game plan: get the ball past the opponent
			-- level 2: +move speed / +ball speed
			-- level 3: 
			-- level 4: 
			-- level 5: 
			-- level 6: lvl 3 buildings unlocked 
			-- level 7: 
			-- level 8: 
			-- level 9: 
		end
	},
	knight={
		extends="leader",
		sprite=3,
		-- colors={2,8,8,8,14,14,15}, -- shadow / four midtones / highlight / skin
		level_up=function(self,level)
			-- extra troop move speed
			-- +2 troops per keep
			-- bonus building health
			-- troop damage tripled
			-- inspire troops on hit

			-- juicy gameplan: summon lotsa troops

			-- level 2: 
			-- level 3: lvl 2 buildings unlocked
			-- level 4: 
			-- level 5: 
			-- level 6: lvl 3 buildings unlocked 
			-- level 7: 
			-- level 8: 
			-- level 9: 
		end
	},
	druid={
		extends="leader",
		sprite=4,
		level_up=function(self,level)
			-- level 2: 
			-- level 3: lvl 2 buildings unlocked
			-- level 4: 
			-- level 5: 
			-- level 6: lvl 3 buildings unlocked 
			-- level 7: 
			-- level 8: 
			-- level 9: 
		end
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
				shake_and_freeze(11,3)
			-- 	self:make_debris(12)
			-- else
			-- 	self:make_debris(5)
			elseif amount>=5 then
				shake_and_freeze(2,1)
			end
		end,
		-- make_debris=function(self,amount)
		-- 	local i
		-- 	for i=1,amount do
		-- 		spawn_entity("debris",self:center_x(),self:center_y(),{
		-- 			vx=rnd(0.8)-0.4,
		-- 			vy=rnd(0.8)-0.4,
		-- 			vz=1.2+rnd(1.5)
		-- 		})
		-- 	end
		-- end,
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
			-- spawn troops
			local num_troops=({1,3,7})[self.upgrades+1]
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
			-- generate gold
			local gold=({25,50,75})[self.upgrades+1]
			self.leader.gold:increase(gold)
			self:pop_text(gold,1,10)
		end
	},
	inn={
		extends="building",
		sprite=3,
		visible_height={8,9,10},
		upgrade_descriptions={{"grants 30","experience"},{"grants 50","experience"}},
		trigger=function(self)
			if self.leader.xp.level<9 then
				-- generate xp
				local xp=({10,30,50})[self.upgrades+1]
				self.leader.xp:increase(xp)
				self:pop_text(xp,3,14,true)
			end
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
		upgrade_descriptions={{"restore 3","hit points"},{"restore 5","hit points"}},
		trigger=function(self)
			-- restore health
			local health=({1,3,5})[self.upgrades+1]
			self.leader.health:increase(health)
			self:pop_text(health,0,8)
		end
	},
	-- game entities
	ball={
		width=3,
		height=3,
		hit_channel=1+2, -- buildings, troops
		damage=20,
		render_layer=6,
		spawn_frames=74,
		-- last_hit_building=nil,
		update=function(self)
			if self.frames_alive>self.spawn_frames then
				self.render_layer=5
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
				-- hit the leaders' goal areas
				if self.x<level_left or self.x>level_right-self.width then
					leader.health:decrease(12)
					self:die()
					shake_and_freeze(13,2)
					-- spawn a new ball
					add(balls,spawn_entity("ball",62,64,{vx=-leader.facing_dir}))
				end
			end
		end,
		draw=function(self,x,y)
			if self.leader then
				pal(7,self.leader.colors[5])
			end
			if self.frames_alive>=self.spawn_frames then
				rectfill2(x,y,self.width,self.height,7)
			elseif self.frames_alive>=self.spawn_frames-45 then
				circ(x+1.5,y+1.5,3+flr(self.spawn_frames-self.frames_alive)/2,7)
			end
		end,
		draw_shadow=function(self,x,y)
			if self.frames_alive>=self.spawn_frames then
				rectfill2(x-1,y+1,self.width,self.height,1)
			end
		end,
		on_death=function(self)
			del(balls,self)
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
		is_freeze_frame_immune=true,
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
					local required_level=ternary(building.upgrades==0,3,6)
					local description=building.upgrade_descriptions[building.upgrades+1]
					if building.upgrades>=2 then
						description={"no further","upgrades"}
						cost="---"
					elseif self.leader.xp.level<required_level then
						description={"requires","level "..required_level}
					end
					self.leader.text_box:show("upgrade",description,cost)
				-- show repair text
				elseif self.action=="repair" then
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
			return self.action=="build" or building
		end
	},
	real_estate={
		render_layer=3,
		y=39,
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
			self:on_update()
		end,
		draw=function(self,x,y)
			if self.frames_alive>self.hidden_frames then
				self:draw_counter(x,y)
			end
		end,
		increase=function(self,amount)
			self.amount=max(0,self.amount+amount)
			if self.max_amount and self.amount>self.max_amount then
				self.amount=self.max_amount
			end
			self.last_change=ternary(self.amount>0,"increase","decrease")
			self.frames_since_change=0
		end,
		decrease=function(self,amount)
			self:increase(-amount)
		end,
		on_update=noop
	},
	health_counter={
		extends="counter",
		amount=45,
		delayed_amount=45,
		max_amount=45,
		min_tick=999,
		max_tick=999,
		hidden_frames=90,
		draw_counter=function(self,x,y)
			local amount,left=self.delayed_amount,self.leader.is_on_left_side
			-- draw heart
			spr2(0,x+ternary(left,0,46),y-3)
			-- draw purple bar
			local bar_left=x+ternary(left,10,0)
			local fill_left=bar_left+ternary(left,0,45-amount)
			rectfill2(bar_left,y,45,4,2)
			-- draw red fill
			if amount>0 then
				rectfill2(fill_left,y,amount,4,8)
				if amount>9 then
					sspr2(0,63,5,1,fill_left+amount-7,y+1)
				end
			end
			-- round off the bar
			-- todo: cut tokens here if necessary (just do bg_color)
			pset2(bar_left,y,ternary(amount>ternary(left,1,44),2,bg_color))
			pset2(bar_left,y+3)
			pset2(bar_left+44,y,ternary(amount>ternary(left,44,1),2,bg_color))
			pset2(bar_left+44,y+3)
		end
	},
	gold_counter={
		extends="counter",
		amount=150,
		delayed_amount=150,
		min_tick=7,
		max_tick=12,
		max_amount=990,
		hidden_frames=45,
		draw_counter=function(self,x,y)
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
		amount=0,
		delayed_amount=0,
		max_xp=40,
		min_tick=2,
		max_tick=2,
		level=1,
		hidden_frames=0,
		on_update=function(self)
			-- level up
			if self.level<9 and self.delayed_amount>=self.max_xp then
				self.delayed_amount-=self.max_xp
				self.amount-=self.max_xp
				self.max_xp=min(self.max_xp+10,90)
				self.level+=1
				local lines=self.leader:level_up(self.level)
				if self.level==3 then
					lines={"lvl 2 buildings","unlocked"}
				elseif self.level==6 then
					lines={"lvl 3 buildings","unlocked"}
				end
				if not lines then -- todo remove this clause
					lines={"---"}
				end
				self.leader.level_up_notification:show(lines)
			end
		end,
		draw_counter=function(self,x,y)
			-- draw level
			sspr2(11,33,11,3,x,y+1)
			print2(self.level,x+14,y,14)
			if self.level<9 then
				-- draw xp bar
				rectfill2(x,y+6,17,2,2)
				-- draw xp fill
				if self.delayed_amount>0 then
					rectfill2(x,y+6,mid(1,flr(1+16*self.delayed_amount/self.max_xp),17),2,14)
				end
			end
		end
	},
	mana_counter={
		extends="counter",
		hidden_frames=0
	},
	text_box={
		render_layer=9,
		-- is_visible=false,
		-- title=nil,
		-- description=nil,
		-- gold=nil,
		gold_warning_frames=0,
		description_warning_frames=0,
		update=function(self)
			decrement_counter_prop(self,"gold_warning_frames")
			decrement_counter_prop(self,"description_warning_frames")
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
					if self.description_warning_frames%8>4 then
						pal(5,8)
					end
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
			self.is_visible,self.gold_warning_frames,self.description_warning_frames=true,0,0
			self.title,self.description,self.gold=title,description,gold
		end,
		hide=function(self)
			self.is_visible,self.gold_warning_frames=false,0
		end,
		warn_gold=function(self)
			self.gold_warning_frames=32
		end,
		warn_description=function(self)
			self.description_warning_frames=32
		end
	},
	level_up_notification={
		visibility_frames=0,
		update=function(self)
			decrement_counter_prop(self,"visibility_frames")
		end,
		draw=function(self)
			if self.visibility_frames>0 then
				-- draw a black background
				rectfill2(self.x-7,self.y,47+2*7,22,bg_color)
				-- draw a dark blue silhouette of the castle
				local castle=self.leader.castle
				pal(5,1)
				pal(13,1)
				castle:draw(castle.x,castle.y,true)
				pal()
				-- draw the level up notification
				pal(3,self.leader.colors[1])
				pal(11,self.leader.colors[4])
				local y=self.y+max(0,2*(self.visibility_frames-168))
				if #self.lines>1 then
					sspr2(0,65,51,6,self.x-2,y+1)
					print2_center(self.lines[1],self.x+24,y+9,7)
					print2_center(self.lines[2],self.x+24,y+15)
				else
					sspr2(0,65,51,6,self.x-2,y+4)
					print2_center(self.lines[1],self.x+24,y+12,7)
				end
			end
		end,
		show=function(self,lines)
			self.visibility_frames,self.lines=170,lines
		end
	},
	leader_select_screen={
		render_layer=7,
		init=function(self)
			self.selects={
				spawn_entity("leader_select",11,36,{player_num=1}),
				spawn_entity("leader_select",77,36,{player_num=2,highlighted_index=3})
			}
		end,
		update=function(self)
			local selects=self.selects
			if self.frames_to_death<=0 and selects[1].is_selected and selects[2].is_selected then
				selects[1]:lock()
				selects[2]:lock()
				self.frames_to_death=50
				real_estates={
					spawn_entity("real_estate",36),
					spawn_entity("real_estate",90)
				}
				spawn_entity("start_game",0,0,{
					leader_choices={self.selects[1].highlighted_index,self.selects[2].highlighted_index}
				})
			end
		end,
		draw=function(self)
			-- black out the screen
			if self.frames_to_death>0 and self.frames_to_death<=15 then
				fillp(fill_wipe[mid(1,ceil(self.frames_to_death/3),5)])
			end
			rectfill2(0,0,127,128,bg_color)
			fillp()
			if self.frames_to_death<=0 then
				print2_center("choose your character",64,18,6)
			end
			-- vs
			print2_center("vs",64,64,6)
			-- the author
			-- print2_center("created by bridgs",64,106,5)
			-- print2_center("(  bridgs_dev)",64,112,5)
			-- spr2(68,38,110)
		end
	},
	leader_select={
		render_layer=8,
		highlighted_index=1,
		update=function(self)
			if self.frames_to_death<=0 then
				if self.is_selected then
					-- select a leader
					if btnp2(5,self.player_num,true) then
						self.is_selected=false
					end
				else
					-- deselect a leader
					if btnp2(4,self.player_num,true) then
						self.is_selected=true
					-- scroll through the leader options
					elseif btnp2(2,self.player_num,true) then
						self.highlighted_index=ternary(self.highlighted_index==1,4,self.highlighted_index-1)
					elseif btnp2(3,self.player_num,true) then
						self.highlighted_index=ternary(self.highlighted_index==4,1,self.highlighted_index+1)
					end
				end
			end
		end,
		draw=function(self,x,y)
			local constants=leader_constants[self.highlighted_index]
			if not self.is_selected then
				-- draw arrows
				sspr2(110,80+ternary(btn2(2,self.player_num),6,0),9,6,x+15,y)
				sspr2(110,92+ternary(btn2(3,self.player_num),6,0),9,6,x+15,y+59)
			end
			if self.frames_to_death<=0 then
				-- draw description
				local i
				for i=1,2 do
					print2_center(constants.description[i],x+21,y+36+6*i,7)
				end
			end
			-- draw portrait
			sspr2(26+14*self.highlighted_index,71,14,19,x+13,y+20,self.player_num==2)
			-- draw nameplate
			pal(3,constants.colors[1])
			pal(11,constants.colors[4])
			sspr2(0,65+6*self.highlighted_index,40,6,x,y+12)
		end,
		lock=function(self)
			self.frames_to_death=50
		end,
		on_death=function(self)
			spawn_entity("leader_spark",self.x+17,self.y+25,{
				player_num=self.player_num,
				vx=ternary(self.player_num==1,-0.56,0.56)
			})
		end
	},
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
	poof={
		frames_to_death=12,
		render_layer=6,
		draw=function(self,x,y)
			sspr2(21,8+9*flr(self.frames_alive/4),12,9,x,y)
		end
	},
	building_halo={
		frames_to_death=18,
		draw=function(self,x,y)
			sspr2(0,30,11,6,x,y)
		end
	},
	leader_spark={
		vy=-2,
		frames_to_death=50,
		update=function(self)
			self.vy+=0.08
			self:apply_velocity()
		end,
		draw=function(self,x,y)
			sspr2(79,ternary(self.frames_alive%4<2,30,37),5,7,x,y)
		end,
		on_death=function(self)
			-- spawn a leader?
		end
	},
	-- debris={
	-- 	z=0,
	-- 	vz=2,
	-- 	update=function(self)
	-- 		self.z+=self.vz
	-- 		self.vz-=0.2
	-- 		self:apply_velocity()
	-- 		if self.z<0 then
	-- 			self:die()
	-- 		end
	-- 	end,
	-- 	draw=function(self,x,y)
	-- 		pset2(x,y-self.z,6)
	-- 	end,
	-- 	draw_shadow=function(self,x,y)
	-- 		pset2(x-self.z,y,1)
	-- 	end
	-- },
	-- background entities
	castle={
		render_layer=1,
		draw=function(self,x,y,silhouette)
			local colors=self.leader.colors
			local health=self.leader.health.delayed_amount
			local sprite
			if health>26 then
				sprite=0
			elseif health>12 then
				sprite=1
			else
				sprite=2
			end
			pal(8,colors[2])
			pal(11,colors[4])
			pal(14,colors[5])
			if silhouette then
				local i
				for i=5,15 do
					pal(i,1)
				end
			end
			local f=flr(self.frames_alive/3)
			sspr2(27*sprite,98,27,min(30,f)-ternary(f>=30,0,9),x,y+max(0,30-f))
		end
	},
	-- life cycle
	start_game={
		frames_to_death=100,
		on_death=function(self)
			local i
			for i=1,2 do
				local leader_props=leader_constants[self.leader_choices[i]]
				local is_on_left_side=(i==1)
				add(leaders,spawn_entity(leader_props.name,ternary(is_on_left_side,6,119),59,{
					player_num=i,
					colors=leader_props.colors,
					facing_dir=ternary(is_on_left_side,1,-1),
					is_on_left_side=is_on_left_side,
					is_facing_left=not is_on_left_side
				}))
			end
			add(balls,spawn_entity("ball",62,64,{
				vx=ternary(rnd()<0.5,-1,1),
				spawn_frames=180
			}))
		end
	}
}

function _init()
	buttons={{},{}}
	button_presses={{},{}}
	entities={}
	balls={}
	real_estates={}
	-- spawn entities
	leaders={}-- {
		-- spawn_entity("witch",6,59,{
		-- 	player_num=1,
		-- 	facing_dir=1,
		-- 	is_on_left_side=true
		-- }),
		-- spawn_entity("knight",119,59,{
		-- 	player_num=2,
		-- 	facing_dir=-1,
		-- 	is_facing_left=true
		-- })
	-- }
	-- leaders[1].opposing_leader=leaders[2]
	-- leaders[2].opposing_leader=leaders[1]
	spawn_entity("leader_select_screen")
end

function _update()
	-- keep track of counters
	local game_is_running=freeze_frames<=0
	freeze_frames=decrement_counter(freeze_frames)
	if game_is_running then
		game_frames=increment_counter(game_frames)
		screen_shake_frames=decrement_counter(screen_shake_frames)
	end
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
		if entity.is_freeze_frame_immune or game_is_running then
			if decrement_counter_prop(entity,"frames_to_death") then
				entity:die()
			else
				increment_counter_prop(entity,"frames_alive")
				entity:update()
			end
		end
	end
	if game_is_running then
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
		if #leaders>0 then
			local troop
			for troop in all(leaders[1].army.troops) do
				local troop2
				for troop2 in all(leaders[2].army.troops) do
					if troop.x>troop2.x-1 and (((troop.x<troop.x+8))) and troop.y==mid(troop2.y-4,troop.y,troop2.y+4) and troop.health>0 and troop2.health>0 then
						troop:damage(1)
						troop2:damage(1)
					end
				end
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
	-- shake the screen
	local screen_offet_x=x
	if freeze_frames<=0 and screen_shake_frames>0 then
		screen_offet_x=ceil(screen_shake_frames/3)*(game_frames%2*2-1)
	end
	camera(screen_offet_x)
	-- clear the screen
	cls(bg_color)
	-- outline the screen's bounding box
	-- rect(0.5,0.5,126.5,127.5,1)
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
			draw=noop,
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

function shake_and_freeze(s,f)
	screen_shake_frames=max(screen_shake_frames,s)
	freeze_frames=max(freeze_frames,f or 0)
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
3e3e0000000cc000000000000007777005555555b333b333555555555555555555555555333333b05555011111111110666660003bbbe0003bbbe0000d616d00
3e3e0000000cc000000000000007777705555555b3b1b3335555555555555555555555553333b3b055551111111111103bbbe000dd666000dd66600000000000
3e3e0000000cc00000000000000777777555555531b333335555555555555555555555553331b3305555111111111110666660003bbbe0003bbbe00000400000
3e3e0000000ccc00000000077007777775555555333333335555555555555555555555553333333055550111111111106dd66000666660006666600064440000
3e3e00000000cc0000000077770700770555555533333333555555555555555555555555333333305555000000111110666660006616600066166000d4240000
3e3e000000000cc000000077777007700555555533333333555555555555555555555555333333305555000001111110d616d000d616d000d616d000426409a9
3e3e00000000ccc0000000077777777705555555333333335555555555555555555555553333333055550000001111100000000000000000000000002bbb1a9a
3e3e00000000c0cc00000007777777770555555533333333555555555555555555555555333333305555000000011110000000000000000000000000666619a9
3e3e0000000cc00c00000000000077770555555533333333555555553333333300001000333333305555000000111110000000000000000000000000d6161444
3e3e0000000c000cc000000000000007755555553333333355555555333333350001000033333330555500000111111000000000000000000000000000000000
3e3e000000cc000c0ccc000000000077755555553333333355555555333333350000000033333330555500000011111000000000000000000000000000040000
3e3e00000c0000c00000c07700000077755555553333333355555555333333330000000033333330555500000001111000000000000000000000000000244000
3e3e00000c0000c00000077700000000055555553333333355555555333333330000000033333330555500000011111000000000000000000000000002424200
3e3e000cc0c000cc0000077007700000055555553333333355555555333333350000000033333330555500000111111004000000040000000400000022272420
3e3e00cc0000000c0000000007700077055555553333333355555555333333350000000033333330555500000011111644400006444000064440000022777240
333e0cc0c0000000c000000000000777055555553333333355555555333333330000000033333330555500000001111d4240000d4240000d4240000027771720
003ec00000000000cc00000000000770055555553333333333333333333333330010000033333330555500000011111426409a9426409a9426409a9003333300
003e0000000000000cc00000000000000555555533333333333333333333333500010000333333305555000000111112bbb1a9a2bbb1a9a2bbb1a9a00e1eee00
003e0000000000000c0c00000000000775555555333b333333333333333333350010100033333330555500000011111666619a9666619a9666619a9000000000
003e000000000000c000c7700000000775555555b31b333333333333333333330010000033b333b0555500000001111d6161444d6161444d6161444000333300
003e00000000000c000007700000000005555555b333333333333333333333330000000031b333b055550000011111100000000000009a909a909a9000eeee00
00330000000000c0c00000000000000005555555bbb33333333333333333333b000000003333bbb05555000001111110000000000001a9a1a9a1a9a000333300
00a00000a00555555555500000000077055555554bbbbbbbbbbbbbbbbbbbbbbb00000000bbbbbb4006000000011111100000000000019a919a919a9000420400
00a00000a00555555555500000000077055555554444444444444444444444440000000044444440070000000011111000000000000144414441444000422400
000a000a000555555555500000000000000000004444444444444444444444444444444444444440070000001111111000000000000000000000000000444400
000a000a000e00e0e0e0000000000000000000002444444444444444444444444444444444444420777000001111111000000000000000000000000000444400
a000000000ae00e2e0e0000000000000005005502222224444444444444422222222222244222220070000001111111000000000000000000000000000420400
0a0000000a0ee00e00ee025555555555005505551222222222222222222222222222222222222210070000000111111000000000000000000000000000400400
55555555555555555555555555555555002555501111222222222222222222222222222222211110060000000000000000000000000000000040000000ddd000
5555555555555555555555555555555505555550011111112222222222222222222222221111110000000000011111100000000000400000024444000dd6dd00
55555000b0000000055555555555555500555500000111111111111111111111111111111111000000000000011110000040000002444400242422000dd6dd00
555550b0b0b0b00b055555555555555500000000000000111111111111111111111111111000000007000000011111100244000024242202227242000d666d00
0ffff1b1b01b001b05555555555555555555555555555555555555555555555555555555555555567776000000000000242420022272420227772400066b6600
0ff77000000000000000555555555555555555555555555555555555555555555555555555555550070000011111111222724202277724027171720006bbb600
bbbbb0011111111111005555555555555555555555555555555555555555555555555555555555500000000111111002277724027771720277777200066bdd00
bbbb701f777777777f10555555555555555555555555555555555555555555555555555555555550000000011111111277717202333332003331300006666600
bbb77017777777777710555555555555555555555555555555555555555555555555555555555555555500000000000033333000eee1e000eeeee00006616600
bbbb70177777777777105555555555555555555555555555555555555555555555555555555555555555011111111110e1eee000e1eee000e1eee00000000000
bbbbb017777777777710555555555555555555555555555555555555555555555555555555555555555501111111100000000000000000000000000040000000
077770177777777777100b00b00000000000b0b55555555555555555555555555555555555555555555501111111111000000000000000000000000044400000
07777017777777777710bbb00bbb00bbb00bbb055555555555555555555555555555555555555555555500000000000000000000000000000000000040400040
077770177777777777104440044400fbf00999055555555555555555555555555555555555555555555500000011111000000000000000003333330040400040
077770177777777777104440044400fff0099905555555555555555555555555555555555555555555550000011111100000000000000000eeeeee0044440c40
0777701f777777777710bbb00bbb00bbb00bbb05555555555555555555555555555555555555555555550000111111100000000003333000333333004040ccc0
0777701f77777777771080c0080c0080c0080c0555555555555555555555555555555555555555555555000001111110000000000eeee0004200040040cccdd0
0777701ff77777777f100003bb003bb3bbbb3bb003bb03bb005555555555555555555555555555555555000011111110033330000333300042222400ccddccc0
077770111111111111100003bb003bb03bb03bbb03bb03bb0055555555555555555555555555555555550000111111100eeee0000420400044444400000c0000
077770011111111111000003bb003bb03bb03bb3b3bb03bb00555555555555555555555555555555555500111111111003333000042240000422400000ccc000
077770000000000000000003bb3b3bb03bb03bb3b3bb03bb0055555555555555555555555555555555550000111111100420400004444000044440000ccccc00
077770001111111110550003bbbbbbb03bb03bb03bbb0000005555555555555555555555555555555555000011111110042240000422400004224000ccccccc0
0777711177777777715500003bb3bb03bbbb3bb003bb03bb00555555555555555555555555555555555500111111111004444000044440000444400000ccc000
0f7771bf7777f777f1553bb00003bbbb003bbbb03bbbbb03bb555555555555555555555555555555555501111111111004444000044440000420400000ccc000
0f7771b7777779ff11553bb0003bb03bb3bb03bb3bb00003bb555555555555555555555555555555555555555555555004204000042040000400400000ccc000
0ff771b7777f711110553bb0003bb03bb3bbbb003bb00003bb555555555555555555555555555555555555555555555004004000040040000400400000ccc0c0
0ffff1b7f779f10000553bb0003bb03bb003bbbb3bbb0003bb5555555555555555555555555555555555555555555550000000000000000000000000000ccc00
e0eee1111ff9100000553bb0003bbb3bb3bb03bb3bb0000000555555555555555555555555555555555555555555555000000000000000000000000000005d00
555550001111000000553bbbbb03bbbb003bbbb03bbbbb03bb55555555555555555555555555555555555555555555500000000000000000000000000005d000
3bb0003bbbbb3bb03bb3bbbbb3bb0000003bb03bb3bbbbb03bb5555555555555555555555555555555555555555555500000000000000000000000000005d00d
3bb0003bb0003bb03bb3bb0003bb0000003bb03bb3bb3bb03bb5555555555555555555555555555555555555555555500000000000000000006000000005dddd
3bb0003bb0003bb03bb3bb0003bb0000003bb03bb3bb3bb03bb55555555555555555555555555555555555555555555000000000000000000060000000c55dd0
3bb0003bbb003bbb3bb3bbb003bb0000003bb03bb3bbbbb03bb555555555555555555555555555555555555555555550000000000000000006d600000ccc0000
3bb0003bb00003bbbb03bb0003bb0000003bbb3bb3bb00000005555555555555555555555555555555555555555555500ddd00000ddd0000d666d00555c00000
3bbbbb3bbbbb003bb003bbbbb3bbbbb00003bbbb03bb00003bb555555555555555555555555555555555555555555550dd6dd000dd6dd00dd666dd050d000000
0003bb003bb3bbbb3bbbbbb3bbbb03bb03bb000000d00000000cc0000aa0000000000000000000000040000000000040dd6dd00ddd6ddd06d666d6055d000000
0003bb003bb03bb0003bb03bb03bb3bb03bb000000c00000dccc0c0000a00000000000000000888e0042400000004240d666d00dd666dd0666b6660999909999
0003bb003bb03bb0003bb03bb00003bb03bb000000cd000cccc00000000aaaaa0000000000088888e04444000000444066b6600d66b66d066bbb6609fff9fff9
0003bb3b3bb03bb0003bb03bb00003bbbbbb000000dcddccccd00000002a9aaaa00000000aa8888880044400000044206bbb60066bbb660666b6dd09fff9fff9
0003bbbbbbb03bb0003bb03bbb3bb3bb03bb0000000ccdcccc000000022229aaaa00000aaa888998800024421124420066bdd00666b6660666666609fff9fff9
00003bb3bb03bbbb003bb003bbbb03bb03bb0000000cccddccddcc0002224222000000aaaa8888f990000024994000006666600dd666660dd6666609fff9fff9
00003bbbbbb3bb03bb3bbbb3bbbbb3bbbbb0000007662cccccccc0002224444440000988ea9888ff8000002999900000661660066616660666166609fff9fff9
0000003bb003bb03bb03bb03bb0003bb000000007556222cccc0000422224444000008888e288ff8000002294442044000000000000000000000000c99f9f99c
0000003bb003bb03bb03bb03bb0003bb00000000617544224256000922292444a00088888822dd22800002999492044000000000000000000000000cccc3cccc
0000003bb003bbbbbb03bb03bbb003bbbb00000057552442441560092222a449aa008888822222228e0002299992424055555555555555000070000000ccc000
0000003bb003bb03bb03bb03bb0003bb00000000175114441441550f22222a229aa0dd8822d888e2880022b39932424055555555555555000777000000020000
0000003bb003bb03bb3bbbb3bbbbb3bb00000000651dd4411545500f222222229aa0ddd22d88888828002bbb3334420055555555555555007777700000880000
3bb3bb3bb003bb3bbbb03bbbb03bb03bb3bbbbb061dccd4dc155550f422242229aa0dd222d8888777700bb33b334230055555555555555077777770008800080
3bb3bb3bbb03bb03bb03bb03bb3bb03bb003bb0055cccc8ccc16550092292224aaa0d22288887777700bbb3333344b3055555555555555777777777008a88880
3bb3bb3bb3b3bb03bb03bb00003bb03bb003bb005cccccd8cc5665009494429aaaa0d6228777766200bbab3bb9943bb0555555555555555555555550089aa998
3bbbb03bb3b3bb03bb03bb3bbb3bbbbbb003bb005544dd89d94115002f444499aaa026277766688000baabbbb9999bb35555555555555500000000000899aaa9
3bb3bb3bb03bbb03bb03bbb3bb3bb03bb003bb00cc441899844c5170f294449a9a00ff676688880000bbbbbbb3499b33555555555555550000d00000089aaaa9
3bb3bb3bb003bb3bbbb03bbbb03bb03bb003bb00dd4918aa849dd179222992222200ffd628882200003bbbbb3343333055555555555555000ddd00000089aaa9
0003bbbbb03bbbbb03bb03bb3bbbb3bbbbb0000011d491891441117661111994410099466111100000033331142111005555555555555500ddddd00080089990
0003bb03bb3bb03bb3bb03bb03bb03bb03bb00000588888805888888805888cccc005cccccc05cccccaa005aaaaaa05aaa5555555555550ddddddd00030d0000
0003bb03bb3bb03bb3bb03bb03bb03bb03bb0000588805888588805888588c05ccc5ccc05ccc5ccc05aaa5aaa05aaa5aaa555555555555ddddddddd000ddd030
0003bb03bb3bbbbb03bb03bb03bb03bb03bb000058880588858880588858cc05ccc5ccc05ccc5ccc05aaa5aaa05aaa000055555555555577777777700c22cbb0
0003bbb3bb3bb03bb3bbb3bb03bb03bbb3bb00005888058885888000005ccc05ccc5ccc05ccc5cca05aaa5aaa05aaa5aaa555555555555577777775044aa3bb0
0003bbbbb03bb03bb03bbbb03bbbb3bbbbb000005888058885888000005ccc05ccc5ccc05ccc5caa05aaa5aaa05aaa5aaa5555555555550577777500089aabb0
55555555555555555555555555555555555555555888058885888000005ccccccc05ccc05ccc5aaa05aaa05aaaaaaa5aaa55555555555500577750008889a990
55555555555555555555555555555555555555555888588885888000005ccc000005ccc05ccc5aaa05aaa000005aaa5aaa555555555555000575000228eea994
55555555555555555555555555555555555555550588885885888000005ccc0000005cccccc05aaa05aaa05aaaaaa05aaa555555555555000050000244eec444
00000000000005000000000000000000000000005000000000000000000000000005000000000000000000000000000000000000000055000000000022444440
00000000000005000000000000000000000000005000000000000000000000000005000000000000000000000000000000000000000055ddddddddd00cc6c000
00000000000015d00000000000000000000000015d00000000000000000000000015d000000000000000000000000000000000000000550ddddddd000ccc0000
00000000000015d00000000000000000000000015d00000000000000000000000015d0000000000000000000000000577700000000005500ddddd0000cc0000c
000000000001555d00000000000000000000001555d00000000000000000000001555d0000000000000000000000005777000000000055000ddd0000ccc00ccc
000000000001555d00000000000000000000001555d00000000000000000000001515d00000000000000000000000010000000000000550000d00000cc0cccc0
1050500000115555d00000105051050500000115555d00000105051050500000111555d0000010000000000000000010000000000000555555555550ccc00cc0
1555500000155555d00000155551555500000155555d00000155551555500000155555d0000015000000000000000010000000000000555555555550c000cc00
1555d00001111155550000155551555d00001111155550000155551555d00001111155550000115000000000000000101000000000005555555555500000c000
1515d00000011555000000151551515d00000011555000000151551515d0000001155500000015115000000000001011100000000000555555555550000c0000
15155000000155550010001515515155000000155510010001515515155000000155510010001515500000000000111510000000000055555555555555555555
15555000100155550111001555515555000100151150111001555515515000100151150111001555500000000000151150000001000055555555555555555555
15555001110155551111101555d15511001110155551111101155d15511001110155151111101155d00000000000155150000001000055555555555555555555
15555051515155515151515555d15555051515155515151515155d15155051115151515151515155d00000000115151510050515100055555555555555555555
15111555555555555555551115d15111551555555555555551115d15111551155551555555551115d00000011555551551555555510055555555555555555555
158be551555555555551558be55158be511555555555551558be55158be511555515555551558be5510001111555515555551555511055555555555555555555
158be551555551555551558be55158be151555551555551558be55158be151555551555551558be1011015111155551555551555151055555555555555555555
158be555555511155555558be55158be555155511155555558be55158be155155511155555518be5515155115115511155555515555155555555555555555555
155b5555555511155555555b555155b5555555511155555555b555155b5155555511155555155b55511551155515511155555155555555555555555555555555
15555555511211125555555555515555555511211125555555555515555155511211125551155555515511155511211125551155115555555555555555555555
11555551111222221555555555511555551111222221555555555511555551111222221555515555511115551115522221555511555155555555555555555555
00000000011244420000000000000000000011244420000000000000000000011244420000000000000015550155544420000111555055555555555555555555
00000000033422240000000000000000000033422240000000000000000000033422240000000000003315555335522240003331155055555555555555555555
00000000011444440000000000000000000011444440000000000000000000011444440000000000001111551111442550000111110055555555555555555555
00000000011422240000000000000000000011422240000000000000000000011422240000000000000111110011422155000000000055555555555555555555
00000000001244420000000000000000000001244420000000000000000000001244420000000000000000000001242111000000000055555555555555555555
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000055555555555555555555
00000000000044400000000000000000000000044400000000000000000000000044400000000000000000000000044400000000000055555555555555555555
00000000000444440000000000000000000000444440000000000000000000000444440000000000000000000000444440000000000055555555555555555555
00000000000044400000000000000000000000044400000000000000000000000044400000000000000000000000044400000000000055555555555555555555
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
