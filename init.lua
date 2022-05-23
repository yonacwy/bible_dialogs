simple_dialogs = { }

local S = simple_dialogs.intllib  --TODO integrate with intllib

-- simple dialogs by Kilarin

local contextctr = {}
local contextdlg = {}

local chars = {}
chars.tag="="
chars.reply=">"
chars.varopen="@["
chars.varclose="]@"

local helpfile=minetest.get_modpath("simple_dialogs").."/simple_dialogs_help.txt"
local transparentpng=minetest.get_modpath("simple_dialogs").."/transparent.png"

local registered_varloaders={}




--[[ ##################################################################################
Translations
--]]

-- Check for translation method
local S
if minetest.get_translator ~= nil then
	S = minetest.get_translator("simple_dialogs") -- 5.x translation function
else
	if minetest.get_modpath("intllib") then
		dofile(minetest.get_modpath("intllib") .. "/init.lua")
		if intllib.make_gettext_pair then
			gettext, ngettext = intllib.make_gettext_pair() -- new gettext method
		else
			gettext = intllib.Getter() -- old text file method
		end
		S = gettext
	else -- boilerplate function
		S = function(str, ...)
			local args = {...}
			return str:gsub("@%d+", function(match)
				return args[tonumber(match:sub(2))]
			end)
		end
	end
end

simple_dialogs.intllib = S


--[[ *******************************************************************************
Methods used when integrating simple_dialogs with an entity mod
--]]

--this should be used by your entity mod to load variable that you want to be available for dialogs
--example:
--		simple_dialogs.register_varloader(function(npcself,playername)
--		simple_dialogs.load_dialog_var(npcself,"NPCNAME",npcself.nametag)
--		simple_dialogs.load_dialog_var(npcself,"STATE",npcself.state)
--		simple_dialogs.load_dialog_var(npcself,"FOOD",npcself.food)
--		simple_dialogs.load_dialog_var(npcself,"HEALTH",npcself.food)
--		simple_dialogs.load_dialog_var(npcself,"owner",npcself.owner)
--	end)--register_on_leaveplayer
function simple_dialogs.register_varloader(func)
	registered_varloaders[#registered_varloaders+1]=func
	minetest.log("simple_dialogs-> register_varloader "..#registered_varloaders)
end


--the dialog control formspec is where an owner can create a dialog for an npc


--this creates and displays an independent dialog control formspec
--dont use this if you are trying to integrate dialog controls with another formspec
function simple_dialogs.show_dialog_controls_formspec(pname,npcself)
	contextctr[pname]=simple_dialogs.set_npc_id(npcself) --store the npc id in local context so we can use it when the form is returned.  (cant store self)
	-- Make blank formspec
	local formspec = {
		"formspec_version[4]",
		"size[15,7]", 
		}
	--add the dialog controls to the above blank formspec
	simple_dialogs.add_dialog_control_to_formspec(pname,npcself,formspec,0.375,0.375)
	formspec=table.concat(formspec, "")
	minetest.show_formspec(pname, "simple_dialogs:dialog_controls", formspec )
end --show_dialog_controls_formspec


--this adds the dialog controls to an existing formspec, so if you already have a control formspec
--for the npc, then use this to add the dialog controls to that formspec
--you will need to add process_simple_dialog_control_fields to the register_on_player_receive_fields
--function for the formspec
--I THINK this should work if your formspec is a string instead of a table, but I haven't tested that yet.
--TODO: allow control of width?
function simple_dialogs.add_dialog_control_to_formspec(pname,npcself,formspec,x,y)
	local dialogtext=""
	if npcself.dialog and npcself.dialog.text then dialogtext=npcself.dialog.text end
	local x2=x
	local y2=y+5
	local x3=x2+2
	local x4=x3+2
	local formspecstr=""
	local passedInString="NO"
	if type(formspec)=="string" then
		formspecstr=formspec
		formspec={}
		passedInString="YES"
	end
	formspec[#formspec+1]="textarea["..x..","..y..";14,4.8;dialog;"..S("Dialog")..";"..minetest.formspec_escape(dialogtext).."]"
	formspec[#formspec+1]="button["..x2..","..y2..";1.5,0.8;help;"..S("Help").."]"
	formspec[#formspec+1]="button["..x3..","..y2..";1.5,0.8;save;"..S("Save").."]"
	formspec[#formspec+1]="button["..x4..","..y2..";3,0.8;saveandtest;"..S("Save & Test").."]"
	if passedInString=="YES" then
		return formspecstr..table.concat(formspec)
	end
end --add_dialog_control_to_formspec


--if you used add_dialog_control_to_formspec to add the dialog controls to an existing formspec,
--then use THIS in your register_on_player_receive_fields function
function simple_dialogs.process_simple_dialog_control_fields(pname,npcself,fields)
	if fields["save"] or fields["saveandtest"] then
		simple_dialogs.load_dialog_from_string(npcself,fields["dialog"],pname)
	end --save or saveandtest
	if fields["saveandtest"] then
		simple_dialogs.show_dialog_formspec(pname,npcself,"START")
	elseif fields["help"] then
		simple_dialogs.dialog_help(pname)
	end
end --process_simple_dialog_control_fields



--this function lets you load a dialog for an npc from a file.  So you can store predetermined dialogs
--as text files and load them for special npc or types of npcs (pirates, villagers, blacksmiths, guards, etc)
--we take modname as a parameter because you might have dialogs in a different mod that uses this mod
function simple_dialogs.load_dialog_from_file(npcself,modname,dialogfilename)
	local file = io.open(minetest.get_modpath(modname).."/"..dialogfilename)
	if file then
		local dialogstr=file:read("*all")
		file.close()
		simple_dialogs.load_dialog_from_string(npcself,dialogstr)
	end
end --load_dialog_from_file



--this will be used to display the actual dialog to a player interacting with the npc
--normally displayed to someone who is NOT the entity owner
--call with tag=START for starting a dialog, or with no tag and it will default to start.
function simple_dialogs.show_dialog_formspec(pname,npcself,tag)
	if not tag then tag="START" end
	contextdlg[pname]={}
	contextdlg[pname].npcId=simple_dialogs.set_npc_id(npcself) --store the npc id in local context so we can use it when the form is returned.  (cant store self)
	local formspec={
		"formspec_version[4]",
		"size[28,15]", 
		"position[0.05,0.05]",
		"anchor[0,0]",
		"no_prepend[]",        --must be present for below transparent setting to work
		"bgcolor[;neither;]",  --make the formspec background transparent
		"box[0.370,0.4;9.6,8.4;#222222FF]", --draws a box background behind our text area
		simple_dialogs.dialog_to_formspec(pname,npcself,tag)
	}
	formspec=table.concat(formspec,"")
	minetest.show_formspec(pname,"simple_dialogs:dialog",formspec)
end --show_dialog_formspec



--[[ *******************************************************************************
convert string input into Dialog table
--]]


--[[
this is where the whole dialog structure is created.

A typical dialog looks like this:
===Start
Hello, welcome to Jarbinks tower of fun!
>jarbink:who is jarbink?
>name:who are you?
>directions:How do I get into the tower?

tags start with = in pos 1 and can look like ===Start   or  =Treasure(5) (any number of ='s are ok as long as there is 1 in pos 1)
a number in parenthesis after the tag name is a "weight" for that entry, which effects how frequently it is chosen.
weight is optional and defaults to 1.
you can have multiple tags with the same name, each gets a number, "subtag", 
when you reference that tag one of the multiple results will be chosen randomly
tags can only contain letters, numbers, underscores, and dashes, all other characters are stripped (letters are uppercased)

After the tag is the "say", this is what the npc says for this tag.

Replies start with > in position 1, and are followed by a target and a colon.  The target is the "tag" this replay takes you to.
the reply follows the colon

You can also add commands, command start with a : in position 1
possible commands are:
:set varname=value
:if (a==b) then set varname=value
:if ( ((a==b) and (c>d)) or (e<=f)) then set varname=value

note that :if requires that the condition be in parenthesis.

The final structure of the dialog table will look like this:
npcself.dialog.
dlg[tag][subtag].weight                    (the weight for this subtag when chosen by random)
dlg[tag][subtag].say                       (the text of the dialog that the npc says)
dlg[tag][subtag].reply[replycount].target  (what tag this reply will go to)
dlg[tag][subtag].reply[replycount].text    (the text of the reply)
dlg[tag][subtag].cmnd[cmndcount].cmnd      (SET or IF)

dlg[tag][subtag].cmnd[cmndcount].cmnd=SET
dlg[tag][subtag].cmnd[cmndcount].varname   (variable name to be set)
dlg[tag][subtag].cmnd[cmndcount].varval    (value to set the variable to)

dlg[tag][subtag].cmnd[cmndcount].cmnd=IF
dlg[tag][subtag].cmnd[cmndcount].condstr   (the condition string, a==b etc, must be in parens)
dlg[tag][subtag].cmnd[cmndcount].ifcmnd.cmnd  (SET for now, GOTO later?, entire structure of subcommand will be here)

--]]
--TODO: split the huge ifelse into methods?
function simple_dialogs.load_dialog_from_string(npcself,dialogstr,pname)  --TODO:pname is not used in here anywhere, remove it?
	npcself.dialog = {}
	npcself.dialog.dlg={}
	npcself.dialog.vars = {}
	--local dlg=npcself.dialog.dlg  --shortcut to make things more readable
	--this function was too long and complicated, so I broke it up into sections
	--the table wk is passed to each sub function as a common work area
	local wk={}  
	wk.tag = ""
	wk.subtag=1
	wk.weight=1
	wk.dlg=npcself.dialog.dlg
	
	--loop through each line in the string (including blank lines) 
	for line in (dialogstr..'\n'):gmatch'(.-)\r?\n' do 
		minetest.log("simple_dialogs->loadstr: line="..line)
		wk.line=line
		local firstchar=string.sub(wk.line,1,1)

		if firstchar == chars.tag then  --we found a tag, process it
			simple_dialogs.load_dialog_tag(wk)
		elseif firstchar == chars.reply and wk.tag ~= "" then  --we found a reply, process it
			simple_dialogs.load_dialog_reply(wk)
		elseif firstchar==":" then --commands
			local spc=string.find(wk.line," ",2)
			if spc then
				local cmnd=string.upper(string.sub(wk.line,2,spc-1))
				local str=string.sub(wk.line,spc+1) --rest of line without the command				
				--minetest.log("simple_dialogs-> ***ldfs c="..c.." cmnd="..cmnd.." str="..str)
				if cmnd=="SET" then
					minetest.log("simple_dialogs-> ldfs cmnd=set")
					local cmndx=simple_dialogs.load_dialog_cmnd_set(str)
					local cmndcount=#wk.dlg[wk.tag][wk.subtag].cmnd+1
					if cmndx then wk.dlg[wk.tag][wk.subtag].cmnd[cmndcount]=cmndx end
				elseif cmnd=="IF" then
					simple_dialogs.load_dialog_cmnd_if(wk,str)
				end --if IF
			end --if spc
		--we check that a tag is set to avoid errors, just in case they put text before the first tag
		--we check that replycount=0 because we are going to ignore any text between the replies and the next tag
		elseif wk.tag~="" and #wk.dlg[wk.tag][wk.subtag].reply==0 then  --we found a dialog line, process it
			--doing this every time is overkill, but avoids the problem of a tag without replies not recording the say
			--TODO: why bother with the say variable at all?
			wk.dlg[wk.tag][wk.subtag].say=wk.dlg[wk.tag][wk.subtag].say..wk.line.."\n"
		end
	end --for line in dialog
	--now double check that every entry has at least 1 reply
	for t,v in pairs(wk.dlg) do
		for st=1,#wk.dlg[t],1 do
			--I could also FORCE an end tag onto every replylist that didn't have one. consider that in the future.
			if not wk.dlg[t][st].reply or not wk.dlg[t][st].reply[1] then
				wk.dlg[t][st].reply={}
				wk.dlg[t][st].reply[1]={}
				wk.dlg[t][st].reply[1].target="END"
				wk.dlg[t][st].reply[1].text="END"
			end --if
		end --for st
	end --for t
	npcself.dialog.text=dialogstr
	minetest.log("simple_dialogs-> ldfs end dlg="..dump(wk.dlg))
end --load_dialog_from_string


--this function is used to load a TAG into the dialog table in load_dialog_from_string 
--wk is our working area variables.
--tags will be in the form of
--=tagname(weight)
--weight is optional, and there can be any number of equal signs
function simple_dialogs.load_dialog_tag(wk)
	wk.tag=wk.line  --this might still include weight, = signs will be stripped off when we filter
	--get the weight from parenthesis
	weight=1
	local i, j = string.find(wk.line,"%(") --look for open parenthesis
	local k, l = string.find(wk.line,"%)") --look for close parenthesis
	--if ( and ) both exist, and the ) is after the (
	if i and i>0 and k and k>i then --found weight
		wk.tag=string.sub(wk.line,1,i-1) --cut the (weight) out of the tagname
		local w=string.sub(wk.line,i+1,k-1) --get the number in parenthesis (weight)
		weight=tonumber(w)
		if weight==nil or weight<1 then weight=1 end
		minetest.log("simple_dialogs->ldt line="..wk.line.." tag="..wk.tag.." i="..i.." k="..k.." w="..w)
	end
	--strip tag down to only allowed characters
	wk.tag=simple_dialogs.tag_filter(wk.tag) --this also strips all leading = signs
	wk.subtag=1
	if wk.dlg[wk.tag] then --existing tag
		--minetest.log("simple_dialogs->ldt tag="..wk.tag.." subtag="..wk.subtag)
		wk.subtag=#(wk.dlg[wk.tag])+1
		wk.weight=wk.dlg[wk.tag][wk.subtag-1].weight+wk.weight  --add previous weight to current weight
		--weight is always the maximum number rolled that returns this subtag
		--TODO: further notes on weight?  here or in readme?
	else --if this is a new tag
		wk.dlg[wk.tag]={} 
	end
	wk.dlg[wk.tag][wk.subtag]={}
	wk.dlg[wk.tag][wk.subtag].say=""
	wk.dlg[wk.tag][wk.subtag].weight=wk.weight
	wk.dlg[wk.tag][wk.subtag].reply={}
	wk.dlg[wk.tag][wk.subtag].cmnd={}
end --load_dialog_tag


--this function is used to load a REPLY into the dialog table in load_dialog_from_string
--wk is our working area variables.
--replies will be in the form of
-->target:replytext
--target is the tag we will go to if this reply is clicked
--replytext is the text that will be shown for the reply
function simple_dialogs.load_dialog_reply(wk)
	--split into target and reply
	local i, j = string.find(wk.line,":")
	if i==nil then 
		i=string.len(wk.line)+1 --if they left out the colon, treat the whole line as the tag
	end
	local replycount=#wk.dlg[wk.tag][wk.subtag].reply+1
	wk.dlg[wk.tag][wk.subtag].reply[replycount]={}
	wk.dlg[wk.tag][wk.subtag].reply[replycount].target=simple_dialogs.tag_filter(string.sub(wk.line,2,i-1))
	--the match below removes leading spaces
	wk.dlg[wk.tag][wk.subtag].reply[replycount].text=string.match(string.sub(wk.line,i+1),'^%s*(.*)')
	if wk.dlg[wk.tag][wk.subtag].reply[replycount].text=="" then
		wk.dlg[wk.tag][wk.subtag].reply[replycount].text=string.sub(wk.line,2,i-1)
	end
end --load_dialog_reply


--this function is used to load a SET cmnd into the dialog table in load_dialog_from_string and in load_dialog_if
--str is the string after the :set and should be in the format of varname=varval
--note that this works a bit differently than the other load_dialog functions.
--it returns a table cmnd.  That way this can be used not only for primary set commands,
--but also for if subcommands
function simple_dialogs.load_dialog_cmnd_set(str)  --pass dlg[tag][subtag].cmnd[#
	local cmnd=nil
	local eq=string.find(str,"=")
	if eq then
		--minetest.log("simple_dialogs-> scs eq")
		local varname=string.sub(str,1,eq-1)
		local varval=string.sub(str,eq+1)
		--minetest.log("simple_dialogs-> scs varname="..varname.." varval="..varval)
		if varval then
			cmnd={}
			cmnd.cmnd="SET"
			cmnd.varname=varname
			cmnd.varval=varval
			---minetest.log("simple_dialogs-> scs after dlg["..tag.."]["..subtag.."].cmnd="..dump(dlg[tag][subtag].cmnd))
			--note that we have NOT populated any vars at that point, that happens when the dialog is actually displayed
		end --if varval
	end --if eq
	return cmnd
end --load_dialog_cmnd_set


--this function is used to load an IF cmnd into the dialog table in load_dialog_from_string 
--wk is our working area variables.
--str is the string after the :if
--if must have all if conditions enclosed in one paren group, even single condition must be in parens
--if (condition) then 
--if ((condition) and (condition) or (condition)) then 
function simple_dialogs.load_dialog_cmnd_if(wk,str)
	--minetest.log("simple_dialogs-> ldfs cmnd=if")
	local grouping=simple_dialogs.build_grouping_list(str,"(",")")
	if grouping.first>0 then --find " THEN " after the last close paren
		local t=string.find(string.upper(str)," THEN ",grouping.list[grouping.first].close)
		if t then
			--minetest.log("simple_dialogs->ldf if t="..t)
			local cmndx={}
			cmndx.cmnd="IF"
			cmndx.condstr=string.sub(str,1,t-1)
			local thenstr=simple_dialogs.trim(string.sub(str,t+6)) --trim ensures no leading spaces
			local spc=string.find(thenstr," ")
			if spc then
				local subcmnd=string.upper(string.sub(thenstr,1,spc-1))
				if subcmnd=="SET" then
					local ifcmnd=simple_dialogs.load_dialog_cmnd_set(string.sub(thenstr,spc+1))
					if ifcmnd then
						cmndx.ifcmnd=ifcmnd
						local cmndcount=#wk.dlg[wk.tag][wk.subtag].cmnd+1
						wk.dlg[wk.tag][wk.subtag].cmnd[cmndcount]=cmndx
					end --if ifcmnd
				end --if subcmnd=set
			end --if spc
		end --if t
	end --if grouping.first
	--minetest.log("simple_dialogs-> ldfs if bot dlg["..wk.tag.."]["..wk.subtag.."].cmnd["..c.."]="..dump(wk.dlg[wk.tag][wk.subtag].cmnd[c]))
end --load_dialog_cmnd_if




--[[ *******************************************************************************
convert Dialog table into a formspec
--]]

--[[
this is the other side of load_dialog_from_string.  dialog_to_formspec turns a dialog table into 
a formspec with the say text and reply list.
this is when variables are substituted, functions executed, and commands run.

a quick note on weight.  the weight number for each subtag is the maximum weight for that tag.
So, for example, if you have three treasure tags like this
=Treasure(2)
=Treasure(4)
=Treasure(7)
you will get weights like this:
dlg[Treasure][1].weight=2
dlg[Treasure][2].weight=6    (2+4=6)
dlg[Treasure][3].weight=13   (6+7=13)
this means we can just roll a random number between 1 and 13,
then select the first subtag for which our random number is less than or equal to its weight.
--]]
function simple_dialogs.dialog_to_formspec(pname,npcself,tag)
	--minetest.log("simple_dialogs->gdtar: pname="..pname.." tag="..tag)
	--minetest.log("simple_dialogs->gdtar: npcself="..dump(npcself))
	--first we make certain everything is properly defined.  if there is an error we do NOT want to crash
	--but we do return an error message that might help debug.
	local errlabel="label[0.375,0.5; ERROR in dialog_to_formspec, "
	if not npcself then return errlabel.." npcself not found]" 
	elseif not npcself.dialog then return errlabel.." npcself.dialog not found]" 
	elseif not tag or tag==nil then return errlabel.." tag passed was nil]"
	elseif not npcself.dialog.dlg[tag] then return errlabel.. " tag "..tag.." not found in the dialog]"
	end
	
	local dlg=npcself.dialog.dlg  --shortcut to make things more readable
	
	--add playername to variables IF it was passed in
	if pname then simple_dialogs.save_dialog_var(npcself,"PLAYERNAME",pname) end
	--load any variables from calling mod
	for f=1,#registered_varloaders do
		registered_varloaders[f](npcself,pname)
		--minetest.log("simple_dialogs-> ran registered_varloader "..f)
	end

	local formspec={}
	
	--how many matching tags (subtags) are there  (for example, if there are 3 "TREASURE" tags)
	local subtagmax=#dlg[tag]
	--get a random number between 1 and the max weight
	local rnd=math.random(dlg[tag][subtagmax].weight)
	
	--subtag represents which tag was chosen when you had repeated tags
	local subtag=1
	--we loop through all the matching tags and select the first one for which our random number
	--is less than or equal to that tags weight.
	for t=1,subtagmax,1 do
		--minetest.log("simple_dialogs->gdtar: t="..t.." rnd="..rnd.." tag="..tag.." subtagmax="..subtagmax.." weight="..dlg[tag][t].weight)
		if rnd<=dlg[tag][t].weight then 
			subtag=t
			break 
		end
	end
	--now subtag equals the selected subtag
	--minetest.log("simple_dialogs->gdtar: tag="..tag.." subtag="..subtag)
	--minetest.log("simple_dialogs->gdtar: before formspec npcself.dialog="..dump(npcself.dialog))
	
	--very first, run any commands
	minetest.log("simple_dialogs->gdtar: tag="..tag.." subtag="..subtag)
	minetest.log("simple_dialogs->gdtar: dlg["..tag.."]["..subtag.."]="..dump(dlg[tag][subtag]))
	for c=1,#dlg[tag][subtag].cmnd do
		local cmnd=dlg[tag][subtag].cmnd[c]
		minetest.log("simple_dialogs->gdtar: c="..c.." cmnd="..dump(cmnd))
		--local cmndname=dlg[tag][subtag].cmnd[c].cmnd
		if cmnd.cmnd=="SET" then
			--local varname=dlg[tag][subtag].cmnd[c].varname
			--local varval=dlg[tag][subtag].cmnd[c].varval
			--minetest.log("simple_dialogs-> ===***=== varname="..varname.." varval="..varval)
			--simple_dialogs.save_dialog_var(npcself,varname,varval)  --load the variable (varname filtering and populating vars happens inside this method)
			simple_dialogs.cmnd_set(npcself,cmnd)
		elseif cmnd.cmnd=="IF" then
			minetest.log("simple_dialogs->gdtar if cmnd="..dump(cmnd))
			local condstr=simple_dialogs.populate_vars_and_funcs(npcself,cmnd.condstr)
			minetest.log("simple_dialogs->gdtar if condstr="..condstr)
			local ifgrouping=simple_dialogs.build_grouping_list(condstr,"(",")")
			for i=1,#ifgrouping.list,1 do
				local condsection=simple_dialogs.grouping_section(ifgrouping,i,"EXCLUSIVE")
				minetest.log("simple dialogs->gdtar if i="..i.." ifgrouping="..dump(ifgrouping))
				minetest.log("simple_dialogs->gdtar if condsection="..dump(condsection).." constr="..condstr) 

				local op=simple_dialogs.split_on_operator(condsection)
				minetest.log("simple_dialog->gdtar if op="..dump(op))
				if op then
					local output=""
					if op.operator == ">=" then
						if op.left >= op.right then output="1" else output="0" end
					elseif op.operator == "<=" then
						if op.left <= op.right then output="1" else output="0" end
					elseif op.operator == "==" then
						if op.left == op.right then output="1" else output="0" end
					elseif op.operator == "~=" then
						if op.left ~= op.right then output="1" else output="0" end
					elseif op.operator == ">" then
						if op.left > op.right then output="1" else output="0" end
					elseif op.operator == "<" then
						if op.left < op.right then output="1" else output="0" end
					end --if op.operator
					minetest.log("simple_dialogs->gdtar if output="..output.."<")
					if op and op.operator>"" then --we found an operator
						condstr=simple_dialogs.grouping_replace(ifgrouping,i,output,"EXCLUSIVE")
						minetest.log("simple_dialogs->gdtar if left="..op.left.."| operator="..op.operator.." right="..op.right.."| output="..output.." condstr="..condstr)
					else
						--if no operator found, its HOPEFULLY just and and ors we do nothing.
						minetest.log("simple_dialogs->gdtar if no operator found condstr="..condstr)
					end --if output
				end --if op 
			end --for
			minetest.log("simple_dialogs->gdtar if before calc cond="..condstr)
			--TODO: test multiple parens, change AND to * and OR to +
			condstr=string.gsub(string.upper(condstr),"AND","*")
			condstr=string.gsub(string.upper(condstr),"OR","+")
			minetest.log("simple_dialogs->gdtar if and or subst cond="..condstr)
			local ifrslt=simple_dialogs.sandboxed_math_loadstring(condstr)
			minetest.log("simple_dialogs->gdtar if after calc ifrslt="..ifrslt)
			--now if rslt=0 test failed.  if rslt>0 test succeded
			if ifrslt>0 then
				if cmnd.ifcmnd.cmnd=="SET" then
					minetest.log("simple_dialogs->gdtar if executing set")
					simple_dialogs.cmnd_set(npcself,cmnd.ifcmnd)
				end --ifcmnd SET
			end --ifrst
		end --if cmnd
	end --for c
	
	local say=dlg[tag][subtag].say
	say=simple_dialogs.populate_vars_and_funcs(npcself,say)
	if not say then say="" end
	--
	--now get the replylist
	local replies=""
	for r=1,#dlg[tag][subtag].reply,1 do
		if r>1 then replies=replies.."," end
		local rply=dlg[tag][subtag].reply[r].text
		rply=simple_dialogs.populate_vars_and_funcs(npcself,rply)
		--if string.len(rply)>70 then rply=string.sub(rply,1,70)..string.char(10)..string.sub(rply,71) end
		--TODO: this is a problem, wrapping once works, but is crowded.  wrapping 3 or more times overlaps text.
		--TODO: also, how to determine what the REAL wrap length should be based on player screen width?
		--replies=replies..minetest.formspec_escape(simple_dialogs.wrap(rply,166,"     ",""))
		replies=replies..minetest.formspec_escape(rply)
	end --for
	local x=0.45
	local y=0.5
	local x2=0.375
	local y2=y+8.375
	--TODO: this crashes if there are no replies.  either escape this or default an "end" reply
	formspec={
		"textarea["..x..","..y..";9.4,8;;;"..minetest.formspec_escape(say).."]",
		"textlist["..x2..","..y2..";27,5;reply;"..replies.."]"  --note that replies were escaped as they were added
	}
	--store the tag and subtag in context as well
	contextdlg[pname].tag=tag
	contextdlg[pname].subtag=subtag
	return table.concat(formspec,"")
end --dialog_to_formspec


--[[

--]]

function simple_dialogs.split_on_operator(condstr)
	if condstr then
		local op={}
		find_operator(op,condstr,">=")
		find_operator(op,condstr,"<=")
		find_operator(op,condstr,"==")
		find_operator(op,condstr,"~=")
		find_operator(op,condstr,">")
		find_operator(op,condstr,"<")
		
		minetest.log("simple_dialogs->soo op="..dump(op))
		
		if op.pos then
			op.left=string.sub(condstr,1,op.pos-1)
			op.right=string.sub(condstr,op.pos+#op.operator)
		else --no operator
			op.left=condstr
			op.operator=""
			op.right=""
			op.pos=#condstr+1  --shouldnt matter
		end --if op.pos
		return op
	else return nil
	end --if opstr
end --split_on_operator


function find_operator(op,condstr,operator)
	local p=string.find(condstr,operator)
	--of op was found, AND either op.pos is not set, or p is before previous op.pos
	if p and (not op.pos or p > op.pos) then
		op.operator=operator
		op.pos=p
	minetest.log("simple_dialogs->fo found operator="..operator.." op="..dump(op))
	end --if 
minetest.log("simple_dialogs->fo notfound operator="..operator.." op="..dump(op))
end --find operator


--pass dlg[tag][subtag].cmnd[c] which should contain .varname and .varval
function simple_dialogs.cmnd_set(npcself,cmnd)
	minetest.log("simple_dialogs-> cs bfr cmnd="..dump(cmnd))
	simple_dialogs.save_dialog_var(npcself,cmnd.varname,cmnd.varval)  --load the variable (varname filtering and populating vars happens inside this method)
	minetest.log("simple_dialogs-> cs aft cmnd="..dump(cmnd))
end--cmnd_set


--from http://lua-users.org/wiki/StringRecipes
function simple_dialogs.wrap(str, limit, indent, indent1)
	indent = indent or ""
	indent1 = indent1 or indent
	limit = limit or 72
	local here = 1-#indent1
	local function check(sp, st, word, fi)
		if fi - here > limit then
			here = st - #indent
			return "\n"..indent..word
		end
	end
	return indent1..str:gsub("(%s+)()(%S+)()", check)
end


--this displays the help text
--I need a way to deal with this by language
function simple_dialogs.dialog_help(pname)
	--local file = io.open(minetest.get_modpath("simple_dialogs").."/simple_dialogs_help.txt", "r")
	local file = io.open(helpfile, "r")
	if file then
		--local help
		local helpstr=file:read("*all")
		file.close()
		local formspec={
		"formspec_version[4]",
		"size[15,15]", 
		"textarea[0.375,0.35;14,14;;help;"..minetest.formspec_escape(helpstr).."]"
		}
		minetest.show_formspec(pname,"simple_dialogs:dialoghelp",table.concat(formspec))
	else
		minetest.log("simple_dialogs->dialoghelp: ERROR unable to find simple_dialogs_help.txt in modpath")
	end 
end --dialog_help


minetest.register_on_player_receive_fields(function(player, formname, fields)
	local pname = player:get_player_name()
	if formname ~= "simple_dialogs:dialog" then
		--can NOT clear context here because this can be called from inside the control panel, 
		--and that can be from a DIFFERENT mod where I cannot predict the name
		return 
	end
	--minetest.log("simple_dialogs->receive_fields dialog: fields="..dump(fields))
	if   not contextdlg[pname] 
		or not contextdlg[pname].npcId 
		or not contextdlg[pname].tag 
		or not contextdlg[pname].subtag 
		then 
			minetest.log("simpleDialogs->recieve_fields dialog: ERROR in dialog receive_fields: context not properly set")
			return 
	end
	local npcId=contextdlg[pname].npcId --get the npc id from local context
	local npcself=nil
	npcself=simple_dialogs.get_npcself_from_id(npcId)  --try to find the npcId in the list of luaentities
	local tag=contextdlg[pname].tag
	local subtag=contextdlg[pname].subtag
	--minetest.log("simple_dialogs->receive_fields dialog: tag="..tag.." subtag="..subtag.." npcId="..npcId)
	--minetest.log("simple_dialogs->receive_fields dialog: npcself="..dump(npcself))
	if   not npcself
		or not npcself.dialog
		or not npcself.dialog.dlg[tag]
		or not npcself.dialog.dlg[tag][subtag]
		then 
			minetest.log("simple_dialogs->receive_fields dialog: ERROR in dialog receive_fields: npcself.dialog.dlg[tag][subtag] not found")
			return
	end
	--
	--incoming reply fields look like: fields={ ["reply"] = CHG:1,}
	if fields["reply"] then 
		--minetest.log("simple_dialogs-> sss got back reply!"..dump(fields["reply"]))
		local r=tonumber(string.sub(fields["reply"],5))
		if npcself.dialog.dlg[tag][subtag].reply[r].target == "END" then
			minetest.close_formspec(pname, "simple_dialogs:dialog")
		else
			local newtag=npcself.dialog.dlg[tag][subtag].reply[r].target
			 simple_dialogs.show_dialog_formspec(pname,npcself,newtag)
		end
	end
end) --register_on_player_receive_fields dialog


--------------------------------------------------------------



function simple_dialogs.save_dialog_var(npcself,varname,varval)
	if npcself and varname then
		if not npcself.dialog.vars then npcself.dialog.vars = {} end
		if not varval then varval="" end
		minetest.log("simple_dialogs-> ---sdv bfr varname="..varname.." varval="..varval)
		varname=simple_dialogs.populate_vars_and_funcs(npcself,varname)  --populate vars
		varname=simple_dialogs.varname_filter(varname)  --filter down to only allowed chars
		varval=simple_dialogs.populate_vars_and_funcs(npcself,varval)  --populate vars
		minetest.log("simple_dialogs-> sdv aft varname="..varname.." varval="..varval)
		npcself.dialog.vars[varname] = varval  --add to variable list
		minetest.log("simple_dialogs-> sdv end npcself.dialog.vars="..dump(npcself.dialog.vars))
	end
end --save_dialog_var



function simple_dialogs.get_dialog_var(npcself,varname,defaultval)
	if npcself and varname then
		if not defaultval then defaultval="" end
		if not npcself.dialog.vars then npcself.dialog.vars = {} end
		minetest.log("simple_dialogs-> ---gdv bfr varname="..varname)
		--varname=simple_dialogs.populate_vars_and_funcs(npcself,varname)  --populate vars  should already be done???
		varname=simple_dialogs.varname_filter(varname)  --filter down to only allowed chars, no need for trim since spaces are not allowed
		minetest.log("simple_dialogs-> ---gdv aft varname="..varname)
		if npcself.dialog.vars[varname] then return npcself.dialog.vars[varname]
		else return defaultval
		end
	end
end --get_dialog_var

--------------------------------------------------------------




--[[ *******************************************************************************
Grouping
These would probably be better separated into a different lua, perhaps even a different mod?
--]]





--this function will go through a string and build a list that tells what order
--to process parenthesis (or any other open close delimiter) in.
--example:
--12345678901234
--((3*(21+2))/4)
--list[1].open=5 close=10
--list[2].open=2 close=11
--list[3].open=1 close=14
--note that if you pass this txt that has bad syntax, it will not throw an error, but instead return an empty list
--list[].open and close are inclusive.  it includes the delimeter
--list[].opene and closee are exclusive.  it does NOT include the delimiter
--so in the above example:
--list[1].opene=6 close=9
--list[2].opene=3 close=10
--list[3].opene=2 close=13
--
--if you pass funcname then only entries that start with funcname( are returned in the final list
--for funcname we can NOT just pass funcname( as the opendelim, because if we did, grouping
--would NOT take into account other functions or parenthesis.  example:
--add(goodnums,calc(@[x]@+1))  <- we need add to recognize the calc function or it will get the wrong close delimiter
function simple_dialogs.build_grouping_list(txt,opendelim,closedelim,funcname)
	minetest.log("simple_dialogs-> bgl top, txt="..txt.." funcname="..dump(funcname))
	if funcname then funcname=simple_dialogs.trim(string.upper(funcname)) end
	local grouping={}
	grouping.list={}
	grouping.origtxt=txt --is this useful?
	grouping.txt=txt
	grouping.first=0  --this will store the grouping index of the first delim in the string
	local openstack={}
	local funcstack={}
	local opendelim_len=string.len(opendelim)
	grouping.opendelim_len=opendelim_len
	local closedelim_len=string.len(closedelim)
	grouping.closedelim_len=closedelim_len
	for i=1,string.len(txt),1 do
		if string.sub(txt,i,i+opendelim_len-1)==opendelim then --open delim
			openstack[#openstack+1]=i  --open pos onto stack.
			minetest.log("simple_dialogs-> bgl i="..i.." open  openstack["..#openstack.."]="..openstack[#openstack])
			if funcname and ((i-#funcname)>0) and (string.upper(string.sub(txt,i-#funcname,i-1))==funcname) then
				funcstack[#openstack]=funcname --just a flag to let us know this openstack matches our function
				openstack[#openstack]=i-#funcname
				minetest.log("simple_dialogs-> bgl open <FUNCNAME> openstack["..#openstack.."]="..openstack[#openstack].." funcname="..funcname.." #funcname="..#funcname)
			end
		elseif string.sub(txt,i,i+closedelim_len-1)==closedelim then -- close delim
			minetest.log("simple_dialogs-> bgl i="..i.." close ")
			--if you find parens out of order, just stop and return what you have so far
			if #openstack<1 then return grouping end 
			minetest.log("simple_dialogs-> bgl close openstack="..dump(openstack).." funcstack="..dump(funcstak))
			if (not funcname) or (funcstack[#openstack]) then
				minetest.log("simple_dialogs-> bgl notfuncname or is func")
				local l=#grouping.list+1
				grouping.list[l]={}
				local gll=grouping.list[l]
				gll.open=openstack[#openstack]
				gll.opene=gll.open+(opendelim_len)
				minetest.log("simple_dialogs-> bgl bfr func: gll="..dump(gll))
				if funcname then gll.opene=gll.opene+#funcname end
				gll.close=i+(closedelim_len-1)
				gll.closee=i-1
				--grouping.first is the first delim in the string.  if grouping.first=0 then we have not set it at all
				if grouping.first==0 then grouping.first=l
				elseif gll.open<grouping.list[grouping.first].open then grouping.first=l
				end
				minetest.log("simple_dialogs-> bgl end close: gll="..dump(gll))
			end --if not funcname
			--gll.section=string.sub(grouping.origtxt,gll.open,gll.close)
			--gll.sectione=string.sub(grouping.origtxt,gll.opene,gll.closee)
			table.remove(openstack,#openstack) --remove from stack
			table.remove(funcstack,#openstack+1) --may or may not be there, +1 because we just reduced the size of openstack by one
		end --if
	end --while
	--minetest.log("GGG about to return")
	return grouping
end --build_grouping_list



function simple_dialogs.grouping_section(grouping,i,incl_excl)
	if not incl_excl then incl_excl="INCLUSIVE" end
	minetest.log("GGGs top i="..i.." incl_excl="..incl_excl.." grouping="..dump(grouping))
	local gli=grouping.list[i]
	--minetest.log("GGGs after gli")
	if incl_excl=="INCLUSIVE" then
		--minetest.log("GGGs inclusive")
		return string.sub(grouping.txt,gli.open,gli.close)
	else
		--minetest.log("GGGs exclusive") 
		return string.sub(grouping.txt,gli.opene,gli.closee)
	end
end --grouping_section



function simple_dialogs.grouping_sectione(grouping,i)
	--minetest.log("GGGse i="..i.." grouping="..dump(grouping))
	simple_dialogs.grouping_section(grouping,i,"EXCLUSIVE")
end --grouping_sectione


function simple_dialogs.grouping_replace(grouping,idx,replacewith,incl_excl)
	--minetest.log("***GGGR top grouping="..dump(grouping).." idx="..idx.." replacewith="..replacewith.." incl_excl="..incl_excl)
	if not incl_excl then incl_excl="INCLUSIVE" end
	local s=grouping.list[idx].open
	local e=grouping.list[idx].close
	if incl_excl=="EXCLUSIVE" then 
		s=grouping.list[idx].opene
		e=grouping.list[idx].closee
	end 
	local origlen=e-s+1
	local diff=string.len(replacewith)-origlen
	local txt=grouping.txt
	grouping.txt=string.sub(txt,1,s-1)..replacewith..string.sub(txt,e+1)
	for i=1,#grouping.list,1 do
		local gli=grouping.list[i]
		if gli.open>s then gli.open=gli.open+diff end
		if gli.opene>s then gli.opene=gli.opene+diff end
		if gli.close>s then gli.close=gli.close+diff end
		if gli.closee>s then gli.closee=gli.closee+diff end
	end --for
	--minetest.log("GGGR bot grouping="..dump(grouping))
	--minetest.log("GGGR2 bot origtxt="..grouping.origtxt)
	--minetest.log("GGGR2 bot     txt="..grouping.txt)
return grouping.txt
end--grouping_replace

--[[
--remove all elements from a grouping that open after lastidx
--(used when if processing to be certain no parens after the then are processed)
function simple_dialogs.grouping_clear_after(grouping,lastidx)
	if grouping and lastidx then
		local newgrouping={}
		for i=#grouping.list,1,-1 do  --iterate backwards because we are removing elements
			if grouping.list[i].open>lastidx then table.remove(grouping.list[i]) end
		end
	end
end--grouping_clear_after
--]]

--[[ ##################################################################################
func splitter
--]]



function simple_dialogs.func_splitter(line,funcname,parmcount)
	minetest.log("simple_dialogs->  ---------------funcsplitter funcname="..funcname.." line="..line)
	if not parmcount then parmcount=1 end
	local grouping=simple_dialogs.build_grouping_list(line,"(",")",funcname)
	minetest.log("simple_dialogs-> fs grouping="..dump(grouping))
	for g=1,#grouping.list,1 do
		grouping.list[g].parm={}
		local sectione=simple_dialogs.grouping_section(grouping,g,"EXCLUSIVE") --get section from string
		minetest.log("simple_dialogs-> fs g="..g.." sectione="..sectione)
		local c=1
		while c<=parmcount do
			local comma=string.find(sectione,",")
			if c<parmcount and comma then 
					grouping.list[g].parm[c]=string.sub(sectione,1,comma-1)
					sectione=string.sub(sectione,comma+1)
			else
				grouping.list[g].parm[c]=sectione
				sectione=""
			end
			c=c+1
		end --while
	end --for
	return grouping
end --func_splitter





--[[ ##################################################################################
very generic utilities
--]]

function simple_dialogs.trim(s)
	return s:match "^%s*(.-)%s*$"
end




function simple_dialogs.get_npcself_from_id(npcId)
	if npcId==nil then return nil
	else
		for k, v in pairs(minetest.luaentities) do
			if v.object and v.id and v.id == npcId then
				return v
			end--if v.object
		end--for
	end --if npcId
end--func



--this function checks to see if an entity already has an id field
--if it does not, it creates one
--the format of npcid was inherited from mobs_npc, which inherited it from something else
--and it may change in the future (Which should have no impact on anything) 
function simple_dialogs.set_npc_id(npcself)
	if not npcself.id then
		npcself.id = (math.random(1, 1000) * math.random(1, 10000))
			.. npcself.name .. (math.random(1, 1000) ^ 2)
	end
	return npcself.id
end


--this is just a function for dumping a table to the logs in a readable format
function dump(o)
	if type(o) == 'table' then
		local s = '{ '
		for k,v in pairs(o) do
			if type(k) ~= 'number' then k = '"'..k..'"' end
			s = s .. '['..k..'] = ' .. dump(v) .. ','
		end
	return s .. '} '
	else
		return tostring(o)
	end
end



--[[ ##################################################################################
more simple_dialog specific utilities
--]]




--tags will be upper cased, and have all characters stripped except for letters, digits, dash, and underline
function simple_dialogs.tag_filter(tagin)
	local allowedchars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_%-" --characters allowed in dialog tags %=escape
	return string.upper(tagin):gsub("[^" .. allowedchars .. "]", "")
end --tag_filter



--variable names will be upper cased, and have all characters stripped except for letters, digits, dash, underline, and period
function simple_dialogs.varname_filter(varnamein)
	local allowedchars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_%-%." --characters allowed in variable names %=escape
	return string.upper(varnamein):gsub("[^" .. allowedchars .. "]", "")
end --varname_filter



--ONLY mathmatical symbols allowed. 
function simple_dialogs.calc_filter(mathstrin)
	local allowedchars = "0123456789%.%+%-%*%/%^%(%)" --characters allowed in math	
	return string.upper(mathstrin):gsub("[^" .. allowedchars .. "]", "")
end --calc_filter



--this function populates variables within dialog text
function simple_dialogs.populate_vars(npcself,line)
	if npcself and npcself.dialog.vars then
		local grouping=simple_dialogs.build_grouping_list(line,chars.varopen,chars.varclose)
		--minetest.log("CCC vars="..dump(npcself.dialog.vars))
		for i=1,#grouping.list,1 do
			--local gli=grouping.list[i]
			--minetest.log("CCC beforesectione i="..i.." grouping="..dump(grouping))
			local k=simple_dialogs.grouping_section(grouping,i,"EXCLUSIVE") --get section from string
			--local k=simple_dialogs.varname_filter(sectione)  --k is our key value
			--minetest.log("CCC i="..i.." sectione="..sectione.." k="..k)
			line=simple_dialogs.grouping_replace(grouping,i,simple_dialogs.get_dialog_var(npcself,k),"INCLUSIVE")
		end --for
	end --if
	return line
end --populate_vars


--this function executes the add(var,value) and rmv(var,value) and calc() functions
function simple_dialogs.populate_funcs(npcself,line)
	minetest.log("simple_dialogs-> pf top line="..line)
	if npcself and npcself.dialog.vars and line then
		--CALC   calc(math)
		local grouping=simple_dialogs.func_splitter(line,"CALC",1)
		if grouping then
			minetest.log("simple_dialogs-> pf calc #grouping.list="..#grouping.list)
			for g=1,#grouping.list,1 do
				local mth=grouping.list[g].parm[1]
				mth=simple_dialogs.calc_filter(mth)  --noting but number and mathmatical symbols allowed!
				minetest.log("simple_dialogs-> pf calc filter mth="..mth)
				line=simple_dialogs.sandboxed_math_loadstring(mth)
				minetest.log("simple_dialogs-> pf calc loadstr mth="..mth)
				line=simple_dialogs.grouping_replace(grouping,g,mth,"INCLUSIVE")
			end --for
		end --if grouping CALC
		--ADD  add(variable,stringtoadd)
		local grouping=simple_dialogs.func_splitter(line,"ADD",2)
		if grouping then
			minetest.log("simple_dialogs-> pf add #grouping.list="..#grouping.list)
			for g=1,#grouping.list,1 do
				local var=grouping.list[g].parm[1]  --populate_vars should always already have happened
				local value=grouping.list[g].parm[2]
				minetest.log("simple_dialogs-> pf var="..var.." value="..value)
				--: simple_dialogs-> pf var=dd(list value=singleplayer
				local list=simple_dialogs.get_dialog_var(npcself,var,"|")
				if string.sub(list,-1)~="|" then list=list.."|" end --must always end in |
				minetest.log("simple_dialogs-> dialog.vars="..dump(npcself.dialog.vars))
				minetest.log("simple_dialogs-> bfradd list="..list) 
				if not string.find(list,"|"..value.."|") then
					list=list..value.."|" --safe because we guaranteed the list ends in | above
					line=simple_dialogs.grouping_replace(grouping,g,list,"INCLUSIVE")
				end
				minetest.log("simple_dialogs-> aftadd list="..list) 
			end --for
		end --if grouping ADD
		--RMV  rmv(variable,stringtoremove)
		local grouping=simple_dialogs.func_splitter(line,"RMV",2)
		if grouping then
			for g=1,#grouping.list,1 do
				local var=grouping.list[g].parm[1]  --populate_vars should always already have happened
				local value=grouping.list[g].parm[2]
				local list=simple_dialogs.get_dialog_var(npcself,var)
				minetest.log("simple_dialogs-> pf rmv list="..list.."<")
				list=string.gsub(list,"|"..value.."|","|")
				line=simple_dialogs.grouping_replace(grouping,g,list,"INCLUSIVE")
			end --for
		end --if grouping RMV
		--ISINLIST  isinlist(variable,stringtolookfor)  returns 1(true) or 0(false)
		local grouping=simple_dialogs.func_splitter(line,"ISINLIST",2)
		if grouping then
			for g=1,#grouping.list,1 do
				local var=grouping.list[g].parm[1]  --populate_vars should always already have happened
				local lookfor=grouping.list[g].parm[2]
				local list=simple_dialogs.get_dialog_var(npcself,var)
				local rtn="0"
				if string.find(list,"|"..lookfor.."|") then rtn="1" end  --using string, numbers cause problems sometimes
				line=simple_dialogs.grouping_replace(grouping,g,rtn,"INCLUSIVE")
			end --for
		end --if grouping ISINLIST
	end --if npcself
	minetest.log("simple_dialogs-> pf bot line="..line)
	return line
end --populate_funcs
		

function simple_dialogs.sandboxed_math_loadstring(mth)
	if not mth then return "" end
	--first we filter the string to allow NOTHING but numbers, parentheses, period, and +-*/^
	mth=simple_dialogs.calc_filter(mth)
	--now we sandbox (do not allow arbitrary lua code execution)  
	--This is overkill, the filtering should ensure this is safe, but why not?
	--better too much security than too little
	local env = {loadstring=loadstring} --only loadstring can run
	local f=function() return loadstring("return "..mth.."+0")() end
	setfenv(f,env) --allow function f to only run in sandbox env
	pcall(function() mth=f() end) --pcall ensures this can NOT cause an error
	if not mth then mth="error" end
	return mth
end --sandboxed_math_loadstring



function simple_dialogs.populate_vars_and_funcs(npcself,line)
	if npcself and line then
		line=simple_dialogs.populate_vars(npcself,line)
		line=simple_dialogs.populate_funcs(npcself,line)
	end
	return line
end --populate_vars_and_funcs


--[[ ##################################################################################
registrations
--]]


--when the player exits, wipe out their context entries
minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	contextctr[name] = nil
	contextdlg[name] = nil 
end)--register_on_leaveplayer


--this will only work if you use show_dialog_control_formspec.  If you have integrated the dialog controls 
--into another formspec you will have to call process_simple_dialog_control_fields from your own player receive fields function
minetest.register_on_player_receive_fields(function(player, formname, fields)
	local pname = player:get_player_name()
	if formname ~= "simple_dialogs:dialog_controls" then 
		if contextctr[pname] then contextctr[pname]=nil end
		return 
	end
	--minetest.log("simple_dialogs->recieve controls: fields="..dump(fields))
	local npcId=contextctr[pname] --get the npc id from local context
	local npcself=nil
	if not npcId then return --exit if npc id was not set 
	else npcself=simple_dialogs.get_npcself_from_id(npcId)  --try to find the npcId in the list of luaentities
	end
	if npcself ~= nil then
		simple_dialogs.process_simple_dialog_control_fields(pname,npcself,fields)
	end --if npcself not nil
end) --register_on_player_receive_fields dialog_controls





