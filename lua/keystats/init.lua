-- init.lua in keypress_analyzer

local M = {}

-- Configuration object
M.config = {
  data_file = vim.fn.stdpath('data') .. '/keypresses.log',
  excluded_modes = {
    ['i'] = true,  -- Insert mode
    ['c'] = true,  -- Command-line mode
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
  max_sequence_length = 10,  -- Max length of sequences to consider for antipatterns
  min_pattern_occurrence = 2, -- Minimum times a pattern must occur to be considered
}

-- Internal state
M.state = {
  logging = false,
}

-- Function to log keypresses
local function log_keypress(char)
  -- Get the current mode
  local mode = vim.api.nvim_get_mode().mode

  -- Get the current timestamp
  local timestamp = os.time()

  -- Represent the key as a readable string
  local key = vim.fn.keytrans(char)

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
  vim.notify('Keypress logging started.')
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
    mode_counts[kp.mode] = (mode_counts[kp.mode] or 0) + 1
    total = total + 1
  end

  return mode_counts, total
end

-- Function to compute key frequencies excluding certain modes
local function analyze_keys(keypresses, excluded_modes)
  local key_counts = {}
  local total = 0

  for _, kp in ipairs(keypresses) do
    if not excluded_modes[kp.mode] then
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

  for _, kp in ipairs(keypresses) do
    local key = kp.key
    local mode = kp.mode

    -- Only consider modes that are not excluded
    if not excluded_modes[mode] then
      -- If the key is the same as the last one, accumulate it
      if #current_sequence == 0 or key == current_sequence[#current_sequence].key then
        table.insert(current_sequence, kp)
      else
        -- Process the sequence
        if #current_sequence > 1 then
          local seq_key = current_sequence[1].key
          local seq_length = #current_sequence
          local pattern = seq_key:rep(seq_length)
          sequences[pattern] = sequences[pattern] or {count = 0, total_keys = 0, occurrences = 0}
          sequences[pattern].count = sequences[pattern].count + 1
          sequences[pattern].total_keys = sequences[pattern].total_keys + seq_length
          sequences[pattern].occurrences = sequences[pattern].occurrences + 1
        end
        current_sequence = {kp}
      end
    else
      -- Reset sequence if mode is excluded
      current_sequence = {}
    end
    last_mode = mode
  end

  -- Check for any remaining sequence at the end
  if #current_sequence > 1 then
    local seq_key = current_sequence[1].key
    local seq_length = #current_sequence
    local pattern = seq_key:rep(seq_length)
    sequences[pattern] = sequences[pattern] or {count = 0, total_keys = 0, occurrences = 0}
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
    table.insert(mode_list, {mode = mode, count = count})
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
  table.insert(key_lines, '│──────────────────│───────│───────────│')
  table.insert(key_lines, '│ KEY              │ COUNT │ SHARE (%) │')
  table.insert(key_lines, '│──────────────────│───────│───────────│')

  -- Convert key_counts to a sorted list
  local key_list = {}
  for key, count in pairs(key_counts) do
    table.insert(key_list, {key = key, count = count})
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
  table.insert(pattern_lines, 'Found Antipatterns')
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
    table.insert(pattern_lines, string.format('│ %-13s │ %5d │ %17d │ %23.2f │', item.pattern, item.count, item.total_keys, item.avg_keys))
  end
  table.insert(pattern_lines, '│───────────────│───────│───────────────────│─────────────────────────│')

  -- Combine all lines
  local all_lines = {}
  vim.list_extend(all_lines, mode_lines)
  vim.list_extend(all_lines, key_lines)
  vim.list_extend(all_lines, pattern_lines)

  -- Display in a new buffer
  vim.cmd('tabnew')
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, all_lines)
  vim.bo[buf].filetype = 'plaintext'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'readonly', true)
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

-- Setup function (optional if you need to override defaults)
function M.setup(config)
  M.config = vim.tbl_deep_extend('force', M.config, config or {})
end

-- Create user commands
vim.api.nvim_create_user_command('KeypressStart', function() M.start_logging() end, {})
vim.api.nvim_create_user_command('KeypressStop', function() M.stop_logging() end, {})
vim.api.nvim_create_user_command('KeypressAnalyze', function() M.analyze() end, {})
vim.api.nvim_create_user_command('KeypressClear', function() M.clear_data() end, {})

return M
