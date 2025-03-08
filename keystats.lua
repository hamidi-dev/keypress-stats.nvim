#!/usr/bin/env lua

-- Vim Keypress Analyzer
-- A Lua script to analyze vim keypress logs

local VERSION = "1.0.0"

-- Constants
local NORMAL_MODE = "normal"
local INSERT_MODE = "insert"
local COMMAND_MODE = "command"
local VISUAL_MODE = "visual"
local TERMINAL_MODE = "terminal"

-- Control characters mapping
local CONTROL_CHARS = {
    [string.char(0x1b)] = "<esc>",
    [string.char(0x0D)] = "<cr>",
    [string.char(0x03)] = "<c-c>",
    [string.char(0x16)] = "<c-v>",
    [string.char(0x09)] = "<tab>",
    [string.char(0x08)] = "<bs>",
    [" "] = "<space>",
    [string.char(0x00)] = "^@",
    [string.char(0x01)] = "^A",
    [string.char(0x02)] = "^B",
    [string.char(0x04)] = "^D",
    [string.char(0x05)] = "^E",
    [string.char(0x06)] = "^F",
    [string.char(0x07)] = "^G",
    [string.char(0x0a)] = "^J",
    [string.char(0x0b)] = "^K",
    [string.char(0x0c)] = "^L",
    [string.char(0x0e)] = "^N",
    [string.char(0x0f)] = "^O",
    [string.char(0x10)] = "^P",
    [string.char(0x11)] = "^Q",
    [string.char(0x12)] = "^R",
    [string.char(0x13)] = "^S",
    [string.char(0x14)] = "^T",
    [string.char(0x15)] = "^U",
    [string.char(0x17)] = "^W",
    [string.char(0x18)] = "^X",
    [string.char(0x19)] = "^Y",
    [string.char(0x1a)] = "^Z",
    [string.char(0x1c)] = "^\\",
    [string.char(0x1d)] = "^]",
}

-- Helper functions
local function to_readable(char)
    if CONTROL_CHARS[char] then
        return CONTROL_CHARS[char]
    end
    return char
end

local function is_in_table(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then
            return true
        end
    end
    return false
end

local function sort_by_count(tbl)
    local sorted = {}
    for k, v in pairs(tbl) do
        table.insert(sorted, {key = k, count = v})
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    return sorted
end

local function format_number(num)
    if num >= 1000 then
        return string.format("%.1fK", num / 1000)
    end
    return tostring(num)
end

local function print_table(headers, rows, title)
    if title then
        print("\n" .. title)
    end
    
    -- Calculate column widths
    local widths = {}
    for i, header in ipairs(headers) do
        widths[i] = #header
    end
    
    for _, row in ipairs(rows) do
        for i, cell in ipairs(row) do
            widths[i] = math.max(widths[i], #tostring(cell))
        end
    end
    
    -- Print header row
    local header_format = "│"
    for i, width in ipairs(widths) do
        header_format = header_format .. " %-" .. width .. "s │"
    end
    
    local separator = "│"
    for i, width in ipairs(widths) do
        separator = separator .. string.rep("─", width + 2) .. "│"
    end
    
    print(separator)
    print(string.format(header_format, table.unpack(headers)))
    print(separator)
    
    -- Print data rows
    for _, row in ipairs(rows) do
        local row_strings = {}
        for i, cell in ipairs(row) do
            row_strings[i] = tostring(cell)
        end
        print(string.format(header_format, table.unpack(row_strings)))
    end
    
    print(separator)
end

-- Parser class
local Parser = {}
Parser.__index = Parser

function Parser.new(enable_antipatterns)
    local self = setmetatable({}, Parser)
    self.current_mode = NORMAL_MODE
    self.previous_key = ""
    self.enable_antipatterns = enable_antipatterns
    self.is_search_active = false
    self.is_motion_active = false
    self.sequence_tracker = {
        sequence = 0,
        current_sequence = "",
        is_active = function(self, char)
            if char == string.char(0xEF) or char == string.char(0xBF) or char == string.char(0xBD) then
                self.sequence = self.sequence + 1
                return true
            elseif char == string.char(0x08) and self.sequence == 2 then
                self.current_sequence = "<m-%s>"
                return true
            elseif char == 'k' and self.sequence == 1 then
                self.sequence = self.sequence + 1
                return true
            elseif char == 'b' and self.sequence == 2 then
                self.current_sequence = "<bs>"
                return false
            end
            return false
        end,
        found = function(self)
            return self.current_sequence ~= ""
        end,
        current_sequence = function(self, current_key)
            if self.current_sequence == "<bs>" then
                return self.current_sequence
            end
            return string.format(self.current_sequence, current_key)
        end,
        reset = function(self)
            self.sequence = 0
            self.current_sequence = ""
        end
    }
    return self
end

function Parser:set_new_mode(current_key)
    if current_key == "<esc>" or current_key == "<c-c>" then
        if not self.is_motion_active then
            self.current_mode = NORMAL_MODE
        end
        self.is_motion_active = false
        self.is_search_active = false
        return
    end
    
    if current_key == "<cr>" then
        if self.current_mode == COMMAND_MODE then
            self.current_mode = NORMAL_MODE
        end
        self.is_search_active = false
        self.is_motion_active = false
        return
    end
    
    if self.is_search_active then
        return
    end
    
    if self.is_motion_active then
        self.is_motion_active = false
        return
    end
    
    if current_key == "/" or current_key == "?" then
        if self.current_mode == NORMAL_MODE or self.current_mode == VISUAL_MODE then
            self.is_search_active = true
        end
        return
    end
    
    if current_key == "t" then
        if self.current_mode == COMMAND_MODE and self.previous_key == "l" then
            self.current_mode = TERMINAL_MODE
            return
        end
        if self.current_mode == NORMAL_MODE or self.current_mode == VISUAL_MODE then
            self.is_motion_active = true
            return
        end
    end
    
    if current_key == "i" or current_key == "I" or current_key == "a" or current_key == "A" then
        if self.current_mode == NORMAL_MODE and self.previous_key ~= "d" and self.previous_key ~= "c" then
            self.current_mode = INSERT_MODE
        end
    elseif current_key == "o" or current_key == "O" or current_key == "C" or current_key == "s" or current_key == "S" then
        if self.current_mode == NORMAL_MODE then
            self.current_mode = INSERT_MODE
        end
    elseif current_key == "c" then
        if self.current_mode == NORMAL_MODE and self.previous_key == "c" then
            self.current_mode = INSERT_MODE
        end
    elseif current_key == ":" then
        if self.current_mode == NORMAL_MODE or self.current_mode == VISUAL_MODE then
            self.current_mode = COMMAND_MODE
        end
    elseif current_key == "v" or current_key == "V" or current_key == "<c-v>" then
        if self.current_mode == NORMAL_MODE then
            self.current_mode = VISUAL_MODE
        elseif self.current_mode == VISUAL_MODE then
            self.current_mode = NORMAL_MODE
        end
    elseif current_key == "d" or current_key == "D" or current_key == "p" or current_key == "P" or current_key == "y" or current_key == "Y" then
        if self.current_mode == VISUAL_MODE then
            self.current_mode = NORMAL_MODE
        end
    end
end

function Parser:parse(input, exclude_modes)
    local keymap = {}
    local mode_count = {}
    local antipatterns = {}
    local antipattern_tracker = {
        last_key = "",
        last_mode = "",
        consecutive_key_count = 0,
        max_allowed_repeats = 2,
        
        track = function(self, current_key, current_mode)
            if current_mode ~= NORMAL_MODE and current_mode ~= VISUAL_MODE then
                self.consecutive_key_count = 0
            else
                self:check_normal_mode(current_key, antipatterns)
            end
            
            if current_mode == INSERT_MODE and self.last_mode ~= INSERT_MODE and current_key == "<cr>" then
                if self.last_key == "I" or self.last_key == "A" then
                    local pattern_name = self.last_key .. current_key
                    self:add_antipattern(pattern_name, antipatterns)
                    antipatterns[pattern_name].total_keypresses = antipatterns[pattern_name].total_keypresses + 2
                end
            end
            
            self.last_key = current_key
            self.last_mode = current_mode
        end,
        
        check_consecutive_keys = function(self, current_key, max_allowed_repeats, antipatterns)
            if self.last_key == current_key then
                local pattern_name = string.rep(current_key, max_allowed_repeats + 1) .. "+"
                self.consecutive_key_count = self.consecutive_key_count + 1
                
                if self.consecutive_key_count == max_allowed_repeats then
                    self:add_antipattern(pattern_name, antipatterns)
                    antipatterns[pattern_name].total_keypresses = antipatterns[pattern_name].total_keypresses + max_allowed_repeats + 1
                end
                
                if self.consecutive_key_count > max_allowed_repeats then
                    antipatterns[pattern_name].total_keypresses = antipatterns[pattern_name].total_keypresses + 1
                end
            else
                self.consecutive_key_count = 0
            end
        end,
        
        check_normal_mode = function(self, current_key, antipatterns)
            if current_key == "h" or current_key == "j" or current_key == "k" or current_key == "l" or
               current_key == "b" or current_key == "B" or current_key == "w" or current_key == "W" or
               current_key == "e" or current_key == "E" or current_key == "x" or current_key == "X" then
                self:check_consecutive_keys(current_key, self.max_allowed_repeats, antipatterns)
            elseif current_key == "d" then
                self:check_consecutive_keys(current_key, 3, antipatterns)
            elseif current_key == "i" or current_key == "a" or current_key == "o" or current_key == "O" then
                local pattern_name = self.last_key .. current_key
                
                if self.last_key == "h" and current_key == "a" then
                    self:add_antipattern(pattern_name, antipatterns)
                    antipatterns[pattern_name].total_keypresses = antipatterns[pattern_name].total_keypresses + 2
                end
                
                if self.last_key == "j" and current_key == "O" then
                    self:add_antipattern(pattern_name, antipatterns)
                    antipatterns[pattern_name].total_keypresses = antipatterns[pattern_name].total_keypresses + 2
                end
                
                if self.last_key == "k" and current_key == "o" then
                    self:add_antipattern(pattern_name, antipatterns)
                    antipatterns[pattern_name].total_keypresses = antipatterns[pattern_name].total_keypresses + 2
                end
                
                if self.last_key == "l" and current_key == "i" then
                    self:add_antipattern(pattern_name, antipatterns)
                    antipatterns[pattern_name].total_keypresses = antipatterns[pattern_name].total_keypresses + 2
                end
            end
        end,
        
        add_antipattern = function(self, key, antipatterns)
            if not antipatterns[key] then
                antipatterns[key] = {
                    key = key,
                    count = 0,
                    total_keypresses = 0,
                    avg_keypresses = 0
                }
            end
            
            antipatterns[key].count = antipatterns[key].count + 1
        end
    }
    
    for i = 1, #input do
        local char = input:sub(i, i)
        
        if self.sequence_tracker:is_active(char) then
            goto continue
        end
        
        local current_key
        if self.sequence_tracker:found() then
            current_key = self.sequence_tracker:current_sequence(to_readable(char))
        else
            current_key = to_readable(char)
        end
        
        self.sequence_tracker:reset()
        
        local current_mode = self.current_mode
        
        mode_count[current_mode] = (mode_count[current_mode] or 0) + 1
        self:set_new_mode(current_key)
        
        self.previous_key = current_key
        
        -- Skip if mode is excluded
        if is_in_table(exclude_modes, current_mode) then
            goto continue
        end
        
        keymap[current_key] = (keymap[current_key] or 0) + 1
        
        if self.enable_antipatterns then
            antipattern_tracker:track(current_key, current_mode)
        end
        
        ::continue::
    end
    
    -- Calculate average keypresses for antipatterns
    for k, v in pairs(antipatterns) do
        v.avg_keypresses = v.total_keypresses / v.count
    end
    
    return {
        keymap = keymap,
        mode_count = mode_count,
        antipatterns = antipatterns
    }
end

-- Main application
local function main()
    -- Parse command line arguments
    local args = {...}
    local options = {
        file = nil,
        limit = 0,
        enable_antipatterns = false,
        exclude_modes = {INSERT_MODE, COMMAND_MODE}
    }
    
    local i = 1
    while i <= #args do
        if args[i] == "--file" or args[i] == "-f" then
            options.file = args[i+1]
            i = i + 2
        elseif args[i] == "--limit" or args[i] == "-l" then
            options.limit = tonumber(args[i+1]) or 0
            i = i + 2
        elseif args[i] == "--enable-antipatterns" or args[i] == "-a" then
            options.enable_antipatterns = true
            i = i + 1
        elseif args[i] == "--exclude-modes" or args[i] == "-e" then
            options.exclude_modes = {}
            for mode in string.gmatch(args[i+1], "([^,]+)") do
                table.insert(options.exclude_modes, mode)
            end
            i = i + 2
        elseif args[i] == "--help" or args[i] == "-h" then
            print("Vim Keypress Analyzer v" .. VERSION)
            print("Usage: lua vim-keypress-analyzer.lua [options]")
            print("Options:")
            print("  -f, --file FILE               Path to logfile containing the keystrokes (required)")
            print("  -l, --limit N                 Number of most frequent keys to show (default: 0 = all)")
            print("  -a, --enable-antipatterns     Enable naive antipattern analysis")
            print("  -e, --exclude-modes MODES     Exclude modes from keymap analysis, comma separated list")
            print("                                (default: insert,command)")
            print("  -h, --help                    Show this help message")
            os.exit(0)
        elseif args[i] == "--version" or args[i] == "-v" then
            print("Vim Keypress Analyzer v" .. VERSION)
            os.exit(0)
        else
            print("Unknown option: " .. args[i])
            print("Use --help for usage information")
            os.exit(1)
        end
    end
    
    if not options.file then
        print("Error: No logfile given")
        print("Use --help for usage information")
        os.exit(1)
    end
    
    -- Read the log file
    local file, err = io.open(options.file, "rb")
    if not file then
        print("Error: Could not open logfile '" .. options.file .. "': " .. err)
        os.exit(1)
    end
    
    local content = file:read("*all")
    file:close()
    
    -- Parse the log file
    local parser = Parser.new(options.enable_antipatterns)
    local result = parser:parse(content, options.exclude_modes)
    
    -- Calculate totals
    local total_keypresses = 0
    for _, count in pairs(result.mode_count) do
        total_keypresses = total_keypresses + count
    end
    
    local total_keypresses_without_excluded = 0
    for mode, count in pairs(result.mode_count) do
        if not is_in_table(options.exclude_modes, mode) then
            total_keypresses_without_excluded = total_keypresses_without_excluded + count
        end
    end
    
    -- Print results
    print("\nVim Keypress Analyzer\n")
    
    -- Mode counts
    local mode_rows = {}
    local sorted_modes = sort_by_count(result.mode_count)
    for _, item in ipairs(sorted_modes) do
        local share = (item.count * 100) / total_keypresses
        table.insert(mode_rows, {
            item.key,
            format_number(item.count),
            string.format("%.2f", share)
        })
    end
    
    print_table(
        {"IDENTIFIER (" .. #sorted_modes .. ")", "COUNT", "SHARE (%)"},
        mode_rows,
        "Key presses per mode (total: " .. total_keypresses .. ")"
    )
    
    -- Key map
    local keymap_rows = {}
    local sorted_keys = sort_by_count(result.keymap)
    
    -- Apply limit if specified
    if options.limit > 0 and #sorted_keys > options.limit then
        local limited = {}
        for i = 1, options.limit do
            table.insert(limited, sorted_keys[i])
        end
        sorted_keys = limited
    end
    
    for _, item in ipairs(sorted_keys) do
        local share = (item.count * 100) / total_keypresses_without_excluded
        table.insert(keymap_rows, {
            item.key,
            format_number(item.count),
            string.format("%.2f", share)
        })
    end
    
    -- Format exclude modes for display
    local exclude_modes_str = table.concat(options.exclude_modes, ", ")
    local plural_s = #options.exclude_modes > 1 and "s" or ""
    
    print_table(
        {"IDENTIFIER (" .. #sorted_keys .. ")", "COUNT", "SHARE (%)"},
        keymap_rows,
        "Key presses excluding [" .. exclude_modes_str .. "] mode" .. plural_s .. " (total: " .. total_keypresses_without_excluded .. ")"
    )
    
    -- Antipatterns
    if options.enable_antipatterns then
        print("\nFound Antipatterns")
        
        local antipattern_rows = {}
        local sorted_antipatterns = sort_by_count(result.antipatterns)
        
        if #sorted_antipatterns == 0 then
            print("no antipatterns found, good job :)")
        else
            for _, item in ipairs(sorted_antipatterns) do
                table.insert(antipattern_rows, {
                    item.key,
                    item.count,
                    format_number(item.total_keypresses),
                    string.format("%.2f", item.avg_keypresses)
                })
            end
            
            print_table(
                {"PATTERN (" .. #sorted_antipatterns .. ")", "COUNT", "TOTAL KEY PRESSES", "AVG KEYS PER OCCURRENCE"},
                antipattern_rows
            )
        end
    end
end

-- Run the main function with command line arguments
main(...)

