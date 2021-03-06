--[==========================================================================[
 syncplay.lua: Syncplay interface module for VLC
--[==========================================================================[

 Author: Etoh
 Project: http://syncplay.pl/
 Version: 0.0.9b
 
--[==========================================================================[

 === Installation instructions ===

Place the syncplay.lua file in one of the VLC /lua/intf/ sub-directories. By default this should be:
* Windows (all users): %ProgramFiles%\VideoLAN\VLC\lua\intf\
* Windows (current user): %APPDATA%\VLC\lua\intf\
* Linux (all users): /usr/lib/vlc/lua/intf/
* Linux (current user): ~/.local/share/vlc/lua/intf/
* Mac OS X (all users): /Applications/VLC.app/Contents/MacOS/share/lua/intf/
* Mac OS X (current user): ~/Library/Application Support/org.videolan.vlc/lua/intf/

If a directory does not exist then you may have to create it.

If you copy the file to the 'all users' directory then you may need to re-copy the file when you update VLC.

Note: You may have to copy the VLC 'modules' folder to make it a sub-directory of the 'intf' folder.

 === Commands and responses ===
 = Note: ? denotes optional responses; * denotes mandatory response; uses \n terminator.

 [On connect]
    >> VLC version

 .
    ? >> inputstate-change: [<input/no-input>]
    ? >> filepath-change-notification
    
    * >> playstate: [<playing/paused/no-input>]
    * >> position: [<decimal seconds/no-input>]

 get-interface-version
    * >> interface-version: [syncplay connector version]
    
 get-duration
    * >> duration: [<duration/no-input>]
    
 get-filepath
    * >> filepath: [<filepath/no-input>]
    
 get-filename
    * >> filepath: [<filename/no-input>]
 
 set-position: [decimal seconds]
    ? >> play-error: no-input

 set-playstate: [<playing/paused>]
    ? >> set-playstate-error: no-input

 set-rate: [decimal rate]
    ? >> set-rate-error: no-input

 display-osd: [placement on screen <center/left/right/top/bottom/top-left/top-right/bottom-left/bottom-right>], [duration in seconds], [message]
    ? >> display-osd-error: no-input

 load-file: [filepath]
    * >> load-file-attempted

 close-vlc

 [Unknown command]
    * >> [Unknown command]-error: unknown-command

--]==========================================================================]
require "common"
require "host"

local connectorversion = "0.0.9"

local durationdelay = 500000 -- Pause for get_duration command for increased reliability

local port

local msgterminator = "\n"
local msgseperator = ": "
local argseperator = ", "

local responsemarker = "-response"
local errormarker = "-error"
local notificationmarker = "-notification"

local noinput = "no-input"
local notimplemented = "not-implemented"
local unknowncommand = "unknown-command"
    
local oldfilepath
local oldinputstate
local newfilepath
local newinputstate

-- Start hosting Syncplay interface.

port = tonumber(config["port"])
if (port == nil or port < 1) then port = 4123 end

vlc.msg.info("Hosting Syncplay interface on port: "..port)

h = host.host()

function detectchanges()
    -- Detects changes in VLC to report to Syncplay.
    -- [Used by the polll / "." command]

    local notificationbuffer = ""

        if vlc.object.input() then
            newinputstate = "input"
            newfilepath = get_filepath()
        
            if newfilepath ~= oldfilepath then
                oldfilepath = newfilepath
                notificationbuffer = notificationbuffer .. "filepath-change"..notificationmarker..msgterminator
            end
            
            notificationbuffer = notificationbuffer .. "playstate"..msgseperator..tostring(get_play_state())..msgterminator
            notificationbuffer = notificationbuffer .. "position"..msgseperator..tostring(get_var("time"))..msgterminator                        
        else
            notificationbuffer = notificationbuffer .. "playstate"..msgseperator..noinput..msgterminator
            notificationbuffer = notificationbuffer .. "position"..msgseperator..noinput..msgterminator
            newinputstate = noinput
        end
        
        if newinputstate ~= oldinputstate then
            oldinputstate = newinputstate
            notificationbuffer = notificationbuffer.."inputstate-change"..msgseperator..tostring(newinputstate)..msgterminator
        end
        
    return notificationbuffer
end

function get_args (argument, argcount)
    -- Converts comma-space-seperated values into array of a given size, with last item absorbing all remaining data if needed.
    -- [Used by the display-osd command]
    
    local argarray = {}
    local index
    local i
    local argbuffer
    
    argbuffer = argument

    for i = 1, argcount,1 do
        if i == argcount  then
            if argbuffer == nil then
                argarray[i] = ""
            else
                argarray[i] = argbuffer
            end
        else
            if string.find(argbuffer, argseperator) then
                index = string.find(argbuffer, argseperator)
                argarray[i] = string.sub(argbuffer, 0, index - 1)
                argbuffer = string.sub(argbuffer, index + string.len(argseperator))
            else
                argarray[i] = ""
            end
        end
        
    end
    
    return argarray
    
end


function get_var( vartoget )
    -- [Used by the poll / '.' command to get time]
    
    local response
    local errormsg
    local input = vlc.object.input()
    
    if input then
        response = vlc.var.get(input,tostring(vartoget))
    else
        errormsg = noinput
    end
   
    return response, errormsg
end


function set_var(vartoset, varvalue)
    -- [Used by the set-time and set-rate commands]
    
    local errormsg
    local input = vlc.object.input()
    
    if input then
        vlc.var.set(input,tostring(vartoset),tostring(varvalue))
    else
        errormsg = noinput
    end

    return  errormsg
end

  h:listen( "localhost:"..port)

function get_play_state()
    -- [Used by the get-playstate command]
    
    local response
    local errormsg
    local input = vlc.object.input()
        
        if input then
            response = vlc.playlist.status()
        else
            errormsg = noinput
        end
        
    return response, errormsg
        
end

function get_filepath ()
    -- [Used by get-filepath command]
    
    local response
    local errormsg
    local item
    local input = vlc.object.input()
    
        if input then
            local item = vlc.input.item()
            if item then
                response = vlc.strings.decode_uri(item:uri())
            else
                errormsg = noinput
            end
        else
            errormsg = noinput
        end
        
    return response, errormsg
end

function get_filename ()
    -- [Used by get-filename command]
    
    local response
    local index
    local filename
    filename = errormerge(get_filepath())
    
    if(filename ~= nil) and (filename ~= "") and (filename ~= noinput) then
        index = string.len(tostring(string.match(filename, ".*/")))
        if index then
            response = string.sub(tostring(filename), index+1)
        end
    else
          response = noinput
    end
    
    return response
end

function get_duration ()
    -- [Used by get-duration command]

    local response
    local errormsg
    local item
    local input = vlc.object.input()
    
        if input then
            local item = vlc.input.item()
            if item then
            -- Try to get duration, which might not be available straight away
                local i = 0            
                repeat
                    vlc.misc.mwait(vlc.misc.mdate() + durationdelay)
                    response = vlc.input.item():duration()
                    i = i + 1
                until response > 0 or i > 5
            else
                errormsg = noinput
            end
        else
            errormsg = noinput
        end
        
    return response, errormsg
end
    

function display_osd ( argument )
    -- [Used by display-osd command]
 
    local errormsg
    local osdarray
    local input = vlc.object.input()
    if input then
        osdarray = get_args(argument,3)
        --position, duration, message -> message, , position, duration (converted from seconds to microseconds)
        local osdduration = tonumber(osdarray[2]) * 1000 * 1000
        vlc.osd.message(osdarray[3],channel1,osdarray[1],osdduration)
    else
        errormsg = noinput
    end
    return errormsg
end

function load_file (filepath)
    -- [Used by load-file command]
	
    local uri = vlc.strings.make_uri(filepath)
    vlc.playlist.add({{path=uri}})
    return "load-file-attempted\n"
end
    
function do_command ( command, argument)
    -- Processes all commands sent by Syncplay (see protocol, above).
    
    if command == "." then
        do return detectchanges() end
    end
    local command = tostring(command)
    local argument = tostring(argument)
    local errormsg = ""
    local response = ""    

    if     command == "get-interface-version" then response           = "interface-version"..msgseperator..connectorversion..msgterminator
    elseif command == "get-duration"          then response           = "duration"..msgseperator..errormerge(get_duration())..msgterminator
    elseif command == "get-filepath"          then response           = "filepath"..msgseperator..errormerge(get_filepath())..msgterminator
    elseif command == "get-filename"          then response           = "filename"..msgseperator..errormerge(get_filename())..msgterminator
    elseif command == "set-position"          then           errormsg = set_var("time", tonumber(argument))
    elseif command == "set-playstate"         then           errormsg = set_playstate(argument)
    elseif command == "set-rate"              then           errormsg = set_var("rate", tonumber(argument))
    elseif command == "display-osd"           then           errormsg = display_osd(argument) 
    elseif command == "load-file"             then response           = load_file(argument)
    elseif command == "close-vlc"             then                      vlc.misc.quit()
    else                                                     errormsg = unknowncommand
    end
    
    if (errormsg ~= nil) and (errormsg ~= "") then
        response = command..errormarker..msgseperator..tostring(errormsg)..msgterminator
    end

    return response
    
end


function errormerge(argument, errormsg)
    -- Used to integrate 'no-input' error messages into command responses.
    
    if (errormsg ~= nil) and (errormsg ~= "") then
        do return errormsg end
    end
    
    return argument
end

function set_playstate(argument)
    -- [Used by the set-playstate command]
    
    local errormsg
    local input = vlc.object.input()
    local playstate
    playstate, errormsg = get_play_state()
    
    if playstate ~= "playing" then playstate =    "paused" end
    if ((errormsg ~= noinput) and (playstate ~= argument)) then
        vlc.playlist.pause()
    end
    
    return errormsg
end

    -- main loop, which alternates between writing and reading
while not vlc.misc.should_die() do
        -- accept new connections and select active clients
    local write, read = h:accept_and_select()

        -- handle clients in write mode
    for _, client in pairs(write) do
        client:send()
        client.buffer = ""
        client:switch_status( host.status.read )
    end

        -- handle clients in read mode
        
    for _, client in pairs(read) do
        local str = client:recv(1000)
        local responsebuffer
        if not str then break end
        
        local safestr = string.gsub(tostring(str), "\r", "")
        if client.inputbuffer == nil then client.inputbuffer = "" end
        
        client.inputbuffer = client.inputbuffer .. safestr
            
        while string.find(client.inputbuffer, msgterminator) do
            local index = string.find(client.inputbuffer, msgterminator)
            local request = string.sub(client.inputbuffer, 0, index - 1)
            local command
            local argument
            client.inputbuffer = string.sub(client.inputbuffer, index + string.len(msgterminator))

            if (string.find(request, msgseperator)) then
                index = string.find(request, msgseperator)
                command = string.sub(request, 0, index - 1)
                argument = string.sub(request, index  + string.len(msgseperator))
                
            else
                command = request
            end
            
            if (responsebuffer) then
                responsebuffer = responsebuffer .. do_command(command,argument)
            else
                responsebuffer = do_command(command,argument)
            end

        end
        
        client.buffer = ""
        if (responsebuffer) then
            client:send(responsebuffer)
        end
        client.buffer = ""
        client:switch_status( host.status.write )
    end
    
end
