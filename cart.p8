pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

-- useful no-op function
function noop() end

-- constants
local controllers={1,0}
local level_top=30
local level_bottom=102
local level_left=0
local level_right=127
local bg_color=0

-- input vars
local buttons
local button_presses

-- entity vars
local entities
local leaders
local entity_classes={
	-- leaders
	leader={
		width=2,
		height=15,
		init=function(self)
			local left=self.is_on_left_side
			local props={leader=self}
			-- create ui elements
			self.text_box=spawn_entity("text_box",ternary(left,0,64),104,props)
			self.text_box:show("archery",{"fires arrows","at troops"},100)
			self.health=spawn_entity("health_counter",ternary(left,1,74),2,props)
			self.gold=spawn_entity("gold_counter",ternary(left,41,81),10,props)
			self.xp=spawn_entity("xp_counter",ternary(left,35,75),18,props)			
		end,
		update=function(self)
			-- waddle up and down
			self.move_y=ternary(buttons[self.player_num][3],1,0)-ternary(buttons[self.player_num][2],1,0)
			self.vy=self.move_y
			self:apply_velocity()
			-- keep in bounds
			self.y=mid(level_top-self.height/2+1,self.y,level_bottom-self.height/2-2)
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
			sspr2(16+4*self.sprite_num,43,4,6,x+ternary(self.is_facing_left,4,-6),self:center_y()-4,self.is_facing_left)
		end,
		draw_shadow=function(self,x,y)
			rectfill2(self.x-1,self.y+2,self.width,self.height,1)
			rectfill2(self.x+ternary(self.is_facing_left,2,-7),self:center_y(),5,2,1)
		end,
		hit_ball=function(self,ball)
			local x,y=self.x+ternary(self.is_facing_left,5,-3),self:center_y()
			local dx,dy=mid(-100,ball:center_x()-x,100),mid(-100,ball:center_y()-y,100)
			local dist=sqrt(dx*dx+dy*dy)
			-- adjust ball velocity based on line from center of leader to center of ball
			ball.vx=dx/dist
			ball.vy=dy/dist
		end
	},
	witch={
		extends="leader",
		sprite_num=1,
		colors={5,13,12,12,12,7,4} -- shadow / four midtones / highlight / skin
	},
	thief={
		extends="leader",
		sprite_num=2,
		colors={4,9,9,10,10,15,4} -- shadow / four midtones / highlight / skin
	},
	knight={
		extends="leader",
		sprite_num=3,
		colors={2,8,8,8,14,14,15} -- shadow / four midtones / highlight / skin
	},
	-- game entities
	ball={
		width=3,
		height=3,
		vx=1,
		vy=0,
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
				end
			elseif self.x>level_right-self.width then
				self.x=level_right-self.width
				if self.vx>0 then
					self.vx*=-1
				end
			end
		end,
		draw=function(self,x,y)
			rectfill2(x,y,self.width,self.height,7)
		end,
		draw_shadow=function(self,x,y)
			rectfill2(x-1,y+1,self.width,self.height,1)
		end
	},
	-- ui entities
	counter={},
	health_counter={
		extends="counter",
		amount=42,
		max_amount=42,
		draw=function(self,x,y)
			local amount,left=self.amount,self.leader.is_on_left_side
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
			pset2(bar_left,y,ternary(self.amount>ternary(left,1,41),2,bg_color))
			pset2(bar_left,y+3)
			pset2(bar_left+41,y,ternary(self.amount>ternary(left,41,1),2,bg_color))
			pset2(bar_left+41,y+3)
		end
	},
	gold_counter={
		extends="counter",
		amount=999,
		max_amount=999,
		draw=function(self,x,y)
			-- draw coin
			spr2(1,x-10,y-2)
			-- draw gold amount
			print2(self.amount,x,y,10)
		end
	},
	xp_counter={
		extends="counter",
		amount=50,
		max_amount=100,
		level=9,
		draw=function(self,x,y)
			-- draw level
			sspr2(17,38,11,3,x,y+1)
			print2(self.level,x+14,y,14)
			-- draw xp bar
			rectfill2(x,y+6,17,2,2)
			-- draw xp fill
			if self.amount>0 then
				rectfill2(x,y+6,max(1,flr(17*self.amount/self.max_amount)),2,14)
			end
		end
	},
	mana_counter={
		extends="counter"
	},
	menu={},
	text_box={
		-- is_visible=false,
		-- title=nil,
		-- description=nil,
		-- gold=nil,
		draw=function(self,x,y)
			if self.is_visible then
				-- draw pane
				pal(11,self.leader.colors[3])
				rectfill2(x+5,y,53,23,7)
				sspr2(0,40,5,23,x,y)
				sspr2(0,40,5,23,x+58,y,true)
				-- draw title and gold cost
				if self.gold then
					print2(self.title,x+7,y+2,0)
					spr(2,x+35,y)
					print2(self.gold,x+45,y+2,9)
				-- draw title centered
				else
					print2_center(self.title,x+32,y+2,0)
				end
				-- draw two-line description
				local description=self.description
				if #description>1 then
					print2_center(description[1],x+32,y+10,0)
					print2_center(description[2],x+32,y+16)
				-- draw one-line description
				else
					print2_center(description[1],x+32,y+12,0)
				end
			end
		end,
		show=function(self,title,description,gold)
			self.is_visible=true
			self.title,self.description,self.gold=title,description,gold
		end,
		hide=function(self)
			self.is_visible=false
		end
	},
	level_up_notification={},
	-- background entities
	castle={
		draw=function(self,x,y)
			sspr2(0,98,27,30,x,y)
		end
	}
}

function _init()
	buttons={{},{}}
	button_presses={{},{}}
	entities={}
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
	spawn_entity("ball",62,65)
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
function contains_point(obj,x,y)
	return obj.x<x and x<obj.x+obj.width and obj.y<y and y<obj.y+obj.height
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
0000000000000000000000000000000000000000000000000000000000000000000000000000000055555000000000000000000000000000003b000000060000
0000000000000000000000000000000000000000000000000000000000000000000000000000000055555000001111100000000000000000003bb00006ddd600
0088088000000aa000000990000000000000ccc700000000000000000000000000000000000000005555500001111110000000000000000000100bb006d6d600
08888ee80000aa7a0000999900e0e0ee000ccc700000000000000000000000000000000000000000555550000011111000000000006000000616000006666600
088888e80000aaaa00009999000e00ee0000cccc00000000000000000000000000000000000000005555500000000000000000006ddd6006dd1dd60003bbbe00
0088888000009aaa0000999900e0e0e000000cc00222222222222b22222222222222222222222200555550011111111000600006ddddd606ddddd60006666600
00088800000009a000000990000000000000c0002bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb2055555011111111106ddd60066d6d66066d6d660006dd6600
0000800000000000000000000000000000000000bbb3333333331b333333333b333333333333bbb055555001111111106d6d6000666660066666660006666600
3e3e0000000cc000000005555555555555555555b333b333555555555555555555555555333333b05555501111111110666660003bbbe0003bbbe0000d616d00
3e3e0000000cc000000005555555555555555555b3b1b3335555555555555555555555553333b3b055555111111111103bbbe000dd666000dd66600000000000
3e3e0000000cc00000000555555555555555555531b333335555555555555555555555553331b3305555511111111110666660003bbbe0003bbbe00000400000
3e3e0000000ccc00000005555555555555555555333333335555555555555555555555553333333055555011111111106dd66000666660006666600064440000
3e3e00000000cc0000000555555555555555555533333333555555555555555555555555333333305555500000011110666660006616600066166000d4240000
3e3e000000000cc000000555555555555555555533333333555555555555555555555555333333305555500000111110d616d000d616d000d616d000426409a9
3e3e00000000ccc0000005555555555555555555333333335555555555555555555555553333333055555000000111100000000000000000000000002bbb1a9a
3e3e00000000c0cc00000555555555555555555533333333555555555555555555555555333333305555500000001110000000000000000000000000666619a9
3e3e0000000cc00c00000555555555555555555533333333555555553333333300001000333333305555500000011110000000000000000000000000d6161444
3e3e0000000c000cc000055555555555555555553333333355555555333333350001000033333330555550000011111004000000040000000400000000000000
3e3e000000cc000c0ccc055555555555555555553333333355555555333333350000000033333330555550000001111644400006444000064440000000040000
3e3e00000c0000c00000c55555555555555555553333333355555555333333330000000033333330555550000000111d4240000d4240000d4240000000244000
3e3e00000c0000c00000055555555555555555553333333355555555333333330000000033333330555550000001111426409a9426409a9426409a9002424200
3e3e000cc0c000cc00000555555555555555555533333333555555553333333500000000333333305555500000111112bbb1a9a2bbb1a9a2bbb1a9a022272420
3e3e00cc0000000c0000055555555555555555553333333355555555333333350000000033333330555550000001111666619a9666619a9666619a9022777240
333e0cc0c0000000c000055555555555555555553333333355555555333333330000000033333330555550000000111d6161444d6161444d6161444027771720
003ec00000000000cc0005555555555555555555333333333333333333333333001000003333333055555000000111100000000000009a909a909a9003333300
003e0000000000000cc00555555555555555555533333333333333333333333500010000333333305555500000011110000000000001a9a1a9a1a9a00e1eee00
003e0000000000000c0c05555555555555555555333b33333333333333333335001010003333333055555000000111100000000000019a919a919a9000000000
003e000000000000c000c5555555555555555555b31b333333333333333333330010000033b333b0555550000000111000000000000144414441444000333300
003e00000000000c000005555555555555555555b333333333333333333333330000000031b333b0555550000011111000000000000000000000000000eeee00
00330000000000c0c00005555555555555555555bbb33333333333333333333b000000003333bbb0555550000011111000000000000000000000000000333300
55555555555555555555555555555555555555554bbbbbbbbbbbbbbbbbbbbbbb00000000bbbbbb40555550000011111000000000000000000000000000420400
55555555555555555555555555555555555555554444444444444444444444440000000044444440555550000001111000000000000000000000000000422400
55555555555555555555555555555555555555554444444444444444444444444444444444444440555550000111111000000000000000000040000000444400
55555555555555555555555555555555555555552444444444444444444444444444444444444420555550000111111000000000004000000244440000444400
55555555555555555555555555555555555555552222224444444444444422222222222244222220555550000111111000400000024444002424220000420400
55555555555555555555555555555555555555551222222222222222222222222222222222222210555550000011111002440000242422022272420000400400
55555555555555555555555555555555555555551111222222222222222222222222222222211110555550000000000024242002227242022777240000ddd000
5555555555555555555555555555555555555555011111112222222222222222222222221111110055555000011111122272420227772402717172000dd6dd00
55555000b00000000e00e0e0e000555555555555000111111111111111111111111111111111000055555000011110022777240277717202777772000dd6dd00
555550b0b0b0b00b0e00e2e0e000555555555555000000111111111111111111111111111000000055555000011111127771720233333200333130000d666d00
0ffff1b1b01b001b0ee00e00ee025555555555555555555555555555555555555555555555555555555550000000000033333000eee1e000eeeee000066b6600
0ff770111111111111105555555555555555555555555555555555555555555555555555555555555555500111111110e1eee000e1eee000e1eee00006bbb600
bbbbb1111111111111115555555555555555555555555555555555555555555555555555555555555555500111111000000000000000000000000000066bdd00
bbbb711f777777777f1100b0b0000000555555555555555555555555555555555555555555555555555550011111111000000000000000003333330006666600
bbb771177777777777110bbb0bbb0bbb55555555555555555555555555555555555555555555555555555000000000000000000000000000eeeeee0006616600
bbbb7117777777777711044404440fbf555555555555555555555555555555555555555555555555555551111111111000000000033330003333330000000000
bbbbb117777777777711044404440fff5555555555555555555555555555555555555555555555555555511111111000000000000eeee0004200040040000000
077771177777777777110bbb0bbb0bbb555555555555555555555555555555555555555555555555555551111111111003333000033330004222240044400000
07777117777777777711080c080c080c55555555555555555555555555555555555555555555555555555000000000000eeee000042040004444440040400040
07777117777777777711555555555555555555555555555555555555555555555555555555555555555550000001111003333000042240000422400040400040
07777117777777777711555555555555555555555555555555555555555555555555555555555555555550000011111004204000044440000444400044440b40
0777711f77777777771155555555555555555555555555555555555555555555555555555555555555555000011111100422400004224000042240004040bbb0
0777711f777777777711555555555555555555555555555555555555555555555555555555555555555550000011111004444000044440000444400040bbb330
0777711ff77777777f110003bb003bb3bbbb3bb003bb03bb005555555555555555555555555555555555500001111110044440000444400004204000bb33bbb0
077771111111111111110003bb003bb03bb03bbb03bb03bb005555555555555555555555555555555555500001111110042040000420400004004000000b0000
077770111111111111100003bb003bb03bb03bb3b3bb03bb00555555555555555555555555555555555550011111111004004000040040000400400000bbb000
077770001111111110000003bb3b3bb03bb03bb3b3bb03bb0055555555555555555555555555555555555000011111100000000000000000000000000bbbbb00
077770001111111110550003bbbbbbb03bb03bb03bbb0000005555555555555555555555555555555555500001111110000000000000000000000000bbbbbbb0
0777711177777777715500003bb3bb03bbbb3bb003bb03bb00555555555555555555555555555555555550011111111000000000000000000006000000bbb000
0f7771bf7777f777f1553bb00003bbbb003bbbb03bbbbb03bb555555555555555555555555555555555550111111111000000000000000000006000000bbb000
0f7771b777777bff11553bb0003bb03bb3bb03bb3bb00003bb55555555555555555555555555555555555555555555500000000000000000006d600000bbb000
0ff771b7777f711110553bb0003bb03bb3bbbb003bb00003bb555555555555555555555555555555555555555555555000ddd00000ddd0000d666d0000bbb0b0
0ffff1b7f77bf10000553bb0003bb03bb003bbbb3bbb0003bb55555555555555555555555555555555555555555555500dd6dd000dd6dd00dd666dd0000bbb00
e0eee1111ffb100000553bb0003bbb3bb3bb03bb3bb000000055555555555555555555555555555555555555555555500dd6dd00ddd6ddd06d666d6000005d00
555550001111000000553bbbbb03bbbb003bbbb03bbbbb03bb55555555555555555555555555555555555555555555500d666d00dd666dd0666b66600005d000
3bb0003bbbbb3bb03bb3bbbbb3bb0000003bb03bb3bbbbb5555555555555555555555555555555555555555555555550066b6600d66b66d066bbb6600005d00d
3bb0003bb0003bb03bb3bb0003bb0000003bb03bb3bb3bb555555555555555555555555555555555555555555555555006bbb60066bbb660666b6dd00005dddd
3bb0003bb0003bb03bb3bb0003bb0000003bb03bb3bb3bb5555555555555555555555555555555555555555555555550066bdd00666b66606666666000b55dd0
3bb0003bbb003bbb3bb3bbb003bb0000003bb03bb3bbbbb555555555555555555555555555555555555555555555555006666600dd666660dd6666600bbb0000
3bb0003bb00003bbbb03bb0003bb0000003bbb3bb3bb000555555555555555555555555555555555555555555555555006616600666166606661666555b00000
3bbbbb3bbbbb003bb003bbbbb3bbbbb00003bbbb03bb00055555555555555555555555555555555555555555555555555555555555555555555555550d000000
0003bb003bb3bbbb3bbbbbb3bbbb03bb03bb0000555555555555555555555555555555555555555555555555555555555555555555555555555555555d000000
0003bb003bb03bb0003bb03bb03bb3bb03bb00005555555555555555555555555555555555555555555555555555555555555555555555555555555999909999
0003bb003bb03bb0003bb03bb00003bb03bb000055555555555555555555555555555555555555555555555555555555555555555555555555555559fff9fff9
0003bb3b3bb03bb0003bb03bb00003bbbbbb000055555555555555555555555555555555555555555555555555555555555555555555555555555559fff9fff9
0003bbbbbbb03bb0003bb03bbb3bb3bb03bb000055555555555555555555555555555555555555555555555555555555555555555555555555555559fff9fff9
00003bb3bb03bbbb003bb003bbbb03bb03bb000055555555555555555555555555555555555555555555555555555555555555555555555555555559fff9fff9
00003bbbbbb3bb03bb3bbbb3bbbbb3bbbbb0000055555555555555555555555555555555555555555555555555555555555555555555555555555559fff9fff9
0000003bb003bb03bb03bb03bb0003bb000000005555555555555555555555555555555555555555555555555555555555555555555555555555555b99f9f99b
0000003bb003bb03bb03bb03bb0003bb000000005555555555555555555555555555555555555555555555555555555555555555555555555555555bbbb3bbbb
0000003bb003bbbbbb03bb03bbb003bbbb0000005555555555555555555555555555555555555555555555555555555555555555555555555555555000bbb000
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
