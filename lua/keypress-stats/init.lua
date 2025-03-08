-- init.lua in keypress_analyzer


local M = {}

-- Configuration object
M.config = {
  data_file = vim.fn.stdpath('data') .. '/keypresses.log',
  excluded_modes = {
    ['i'] = true, -- Insert mode
    ['c'] = true, -- Command-line mode
    -- Add other modes to exclude as needed
  },
  mode_map = {
    ['n'] = 'normal',
    ['i'] = 'insert',
    ['v'] = 'visual',
    ['V'] = 'visual_line',
    [''] = 'visual_block', -- This is Ctrl+V in Lua strings
    ['c'] = 'command',
    ['s'] = 'select',
    ['S'] = 'select',
    ['r'] = 'replace',
    ['R'] = 'replace',
    ['t'] = 'terminal',
    -- Add other modes as necessary
  },
  max_sequence_length = 10,   -- Max length of sequences to consider for antipatterns
  min_pattern_occurrence = 2, -- Minimum times a pattern must occur to be considered
  auto_start = false,         -- Whether to start logging automatically on Neovim startup
  use_floating_term = true,   -- Whether to use a floating terminal for analysis
}

-- Internal state
M.state = {
  logging = false,
}

-- Function to check if a key is a mouse event or terminal escape sequence
local function should_ignore_key(key)
  -- Mouse events in Vim/Neovim typically start with "<LeftMouse", "<RightMouse", etc.
  -- Also check for drag events like "<LeftDrag>", release events like "<LeftRelease>",
  -- and scroll wheel events like "<ScrollWheelDown>"
  -- Terminal escape sequences typically contain "<t_" or "<FD>"
  return key:match("^<.*Mouse") ~= nil or 
         key:match("^<.*Drag>") ~= nil or 
         key:match("^<.*Release>") ~= nil or
         key:match("^<ScrollWheel") ~= nil or
         key:match("<t_") ~= nil or
         key:match("<FD>") ~= nil
end

-- Function to log keypresses
local function log_keypress(char)
  -- Represent the key as a readable string
  local key = vim.fn.keytrans(char)
  
  -- Skip mouse events and terminal escape sequences
  if should_ignore_key(key) then
    return
  end

  -- Get the current mode
  local mode = vim.api.nvim_get_mode().mode

  -- Get the current timestamp
  local timestamp = os.time()

  -- Map the mode to a readable name
  local mode_name = M.config.mode_map[mode] or mode

  -- Prepare the data line
  local data_line = string.format('%d,%s,%s\n', timestamp, mode_name, key)

  -- Append the data to the file
  local f = io.open(M.config.data_file, 'a')
  if f then
    f:write(data_line)
    f:close()
  else
    vim.api.nvim_err_writeln('Error opening keypress data file for writing.')
  end
end

-- Function to start logging
function M.start_logging()
  if M.state.logging then
    vim.notify('Keypress logging is already active.')
    return
  end
  M.state.logging = true
  vim.on_key(log_keypress)
end

-- Function to stop logging
function M.stop_logging()
  if not M.state.logging then
    vim.notify('Keypress logging is not active.')
    return
  end
  M.state.logging = false
  vim.on_key(nil)
  vim.notify('Keypress logging stopped.')
end

-- Function to read logged data
local function read_data()
  local keypresses = {}
  local f = io.open(M.config.data_file, 'r')
  if not f then
    vim.api.nvim_err_writeln('Error opening keypress data file for reading.')
    return keypresses
  end

  for line in f:lines() do
    local timestamp, mode, key = line:match('(%d+),([^,]+),(.+)')
    if timestamp and mode and key then
      table.insert(keypresses, {
        timestamp = tonumber(timestamp),
        mode = mode,
        key = key,
      })
    end
  end
  f:close()
  return keypresses
end

-- Function to compute keypresses per mode
local function analyze_modes(keypresses)
  local mode_counts = {}
  local total = 0

  for _, kp in ipairs(keypresses) do
    -- Skip mouse events and terminal escape sequences
    if not should_ignore_key(kp.key) then
      mode_counts[kp.mode] = (mode_counts[kp.mode] or 0) + 1
      total = total + 1
    end
  end

  return mode_counts, total
end

-- Function to compute key frequencies excluding certain modes
local function analyze_keys(keypresses, excluded_modes)
  local key_counts = {}
  local total = 0

  for _, kp in ipairs(keypresses) do
    -- Always include Escape key regardless of mode
    if (kp.key == "<Esc>" or not excluded_modes[kp.mode]) and not should_ignore_key(kp.key) then
      key_counts[kp.key] = (key_counts[kp.key] or 0) + 1
      total = total + 1
    end
  end

  return key_counts, total
end

-- Function to find antipatterns
local function analyze_antipatterns(keypresses, excluded_modes)
  local sequences = {}
  local current_sequence = {}
  local last_mode = ''
  local last_timestamp = 0
  local time_threshold = 1.5  -- 1.5 seconds threshold for considering keys part of the same sequence

  for _, kp in ipairs(keypresses) do
    local key = kp.key
    local mode = kp.mode
    local timestamp = kp.timestamp

    -- Only consider modes that are not excluded and not mouse events or terminal escape sequences
    if not excluded_modes[mode] and not should_ignore_key(key) then
      -- If the key is the same as the last one and within time threshold, accumulate it
      local time_diff = (last_timestamp > 0) and (timestamp - last_timestamp) or 0
      if #current_sequence == 0 or 
         (key == current_sequence[#current_sequence].key and time_diff <= time_threshold) then
        table.insert(current_sequence, kp)
      else
        -- Process the sequence
        if #current_sequence > 1 then
          local seq_key = current_sequence[1].key
          local seq_length = #current_sequence
          local pattern = seq_key:rep(seq_length)
          sequences[pattern] = sequences[pattern] or { count = 0, total_keys = 0, occurrences = 0 }
          sequences[pattern].count = sequences[pattern].count + 1
          sequences[pattern].total_keys = sequences[pattern].total_keys + seq_length
          sequences[pattern].occurrences = sequences[pattern].occurrences + 1
        end
        current_sequence = { kp }
      end
      last_timestamp = timestamp
    else
      -- Reset sequence if mode is excluded or it's a mouse event
      current_sequence = {}
    end
    last_mode = mode
  end

  -- Check for any remaining sequence at the end
  if #current_sequence > 1 then
    local seq_key = current_sequence[1].key
    local seq_length = #current_sequence
    local pattern = seq_key:rep(seq_length)
    sequences[pattern] = sequences[pattern] or { count = 0, total_keys = 0, occurrences = 0 }
    sequences[pattern].count = sequences[pattern].count + 1
    sequences[pattern].total_keys = sequences[pattern].total_keys + seq_length
    sequences[pattern].occurrences = sequences[pattern].occurrences + 1
  end

  return sequences
end

-- Function to analyze and display the results
function M.analyze()
  local keypresses = read_data()
  if #keypresses == 0 then
    vim.api.nvim_out_write('No keypress data to analyze.\n')
    return
  end

  -- Analyze keypresses per mode
  local mode_counts, total_presses = analyze_modes(keypresses)

  -- Prepare mode statistics lines
  local mode_lines = {}
  table.insert(mode_lines, string.format('Key presses per mode (total: %d)', total_presses))
  table.insert(mode_lines, '│─────────────────│───────│───────────│')
  table.insert(mode_lines, '│ MODE            │ COUNT │ SHARE (%) │')
  table.insert(mode_lines, '│─────────────────│───────│───────────│')

  -- Convert mode_counts to a sorted list
  local mode_list = {}
  for mode, count in pairs(mode_counts) do
    table.insert(mode_list, { mode = mode, count = count })
  end
  table.sort(mode_list, function(a, b)
    return a.count > b.count
  end)

  for _, item in ipairs(mode_list) do
    local share = (item.count / total_presses) * 100
    table.insert(mode_lines, string.format('│ %-15s │ %5d │ %8.2f │', item.mode, item.count, share))
  end
  table.insert(mode_lines, '│─────────────────│───────│───────────│')

  -- Analyze key frequencies excluding certain modes
  local key_counts, total_keys = analyze_keys(keypresses, M.config.excluded_modes)

-- Prepare key frequencies lines
  local key_lines = {}
  table.insert(key_lines, string.format('Key presses excluding [insert, command] modes (total: %d)', total_keys))
  table.insert(key_lines, 'Note: Terminal escape sequences and mouse events are filtered out')
  table.insert(key_lines, 'Note: <Esc> key is always included regardless of mode')
  table.insert(key_lines, '│──────────────────│───────│───────────│')
  table.insert(key_lines, '│ KEY              │ COUNT │ SHARE (%) │')
  table.insert(key_lines, '│──────────────────│───────│───────────│')

  -- Convert key_counts to a sorted list
  local key_list = {}
  for key, count in pairs(key_counts) do
    table.insert(key_list, { key = key, count = count })
  end
  table.sort(key_list, function(a, b)
    return a.count > b.count
  end)

  -- Display top 10 keys
  for i = 1, math.min(10, #key_list) do
    local item = key_list[i]
    local share = (item.count / total_keys) * 100
    table.insert(key_lines, string.format('│ %-16s │ %5d │ %8.2f │', item.key, item.count, share))
  end
  table.insert(key_lines, '│──────────────────│───────│───────────│')

  -- Analyze antipatterns
  local patterns = analyze_antipatterns(keypresses, M.config.excluded_modes)

-- Prepare antipatterns lines
  local pattern_lines = {}
  table.insert(pattern_lines, 'Found Antipatterns (repeated keypresses within 1.5 seconds)')
  table.insert(pattern_lines, '│───────────────│───────│───────────────────│─────────────────────────│')
  table.insert(pattern_lines, '│ PATTERN       │ COUNT │ TOTAL KEY PRESSES │ AVG KEYS PER OCCURRENCE │')
  table.insert(pattern_lines, '│───────────────│───────│───────────────────│─────────────────────────│')

  -- Convert patterns table to a list for sorting
  local pattern_list = {}
  for pattern, info in pairs(patterns) do
    if info.count >= M.config.min_pattern_occurrence then
      table.insert(pattern_list, {
        pattern = pattern,
        count = info.count,
        total_keys = info.total_keys,
        avg_keys = info.total_keys / info.occurrences,
      })
    end
  end

  -- Sort by total_keys descending
  table.sort(pattern_list, function(a, b)
    return a.total_keys > b.total_keys
  end)

  -- Display top 10 antipatterns
  for i = 1, math.min(10, #pattern_list) do
    local item = pattern_list[i]
    table.insert(pattern_lines,
      string.format('│ %-13s │ %5d │ %17d │ %23.2f │', item.pattern, item.count, item.total_keys, item.avg_keys))
  end
  table.insert(pattern_lines, '│───────────────│───────│───────────────────│─────────────────────────│')

  -- Combine all lines
  local all_lines = {}
  vim.list_extend(all_lines, mode_lines)
  vim.list_extend(all_lines, key_lines)
  vim.list_extend(all_lines, pattern_lines)

  -- Create a temporary file to store the analysis
  local temp_file = vim.fn.tempname()
  local f = io.open(temp_file, 'w')
  if f then
    for _, line in ipairs(all_lines) do
      f:write(line .. '\n')
    end
    f:close()

    -- Check if snacks is available
    local has_snacks, snacks = pcall(require, "snacks")

    if has_snacks then
      -- Use snacks terminal to display the analysis
      snacks.terminal.open("cat " .. temp_file .. " | less -R",
        { win = { position = "float", width = 0.70, height = 0.95 } })
    else
      -- Fallback to a regular floating window if snacks is not available
      local cmd = "less -R " .. temp_file
      vim.fn.termopen(cmd)

      -- Create a floating window
      local width = math.min(120, vim.o.columns - 10)
      local height = math.min(30, vim.o.lines - 10)
      local row = math.floor((vim.o.lines - height) / 2)
      local col = math.floor((vim.o.columns - width) / 2)

      local buf = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded'
      })

      vim.fn.termopen(cmd)
      vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    end
  else
    vim.api.nvim_err_writeln('Error creating temporary file for analysis.')
  end
end

-- Function to clear keypress data
function M.clear_data()
  local f = io.open(M.config.data_file, 'w')
  if f then
    f:close()
    vim.notify('Keypress data cleared.')
  else
    vim.api.nvim_err_writeln('Error clearing keypress data file.')
  end
end

-- Function to initialize auto-start
local function init_auto_start()
  if M.config.auto_start then
    -- Use a small delay to ensure Neovim is fully initialized
    vim.defer_fn(function()
      M.start_logging()
    end, 100)
  end
end

-- Setup function (optional if you need to override defaults)
function M.setup(config)
  M.config = vim.tbl_deep_extend('force', M.config, config or {})

  -- Initialize auto-start if enabled
  init_auto_start()
end

-- Create user commands
vim.api.nvim_create_user_command('KeypressStart', function() M.start_logging() end, {})
vim.api.nvim_create_user_command('KeypressStop', function() M.stop_logging() end, {})
vim.api.nvim_create_user_command('KeypressAnalyze', function() M.analyze() end, {})
vim.api.nvim_create_user_command('KeypressClear', function() M.clear_data() end, {})

return M
