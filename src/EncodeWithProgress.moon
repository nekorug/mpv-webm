-- Not really a Page, but reusing its functions is pretty useful
class BaseEncodeWithProgress extends Page
	new: (startTime, endTime) =>
		@startTime = startTime
		@endTime = endTime
		@duration = endTime - startTime
		@currentTime = startTime

	draw: =>
		progress = 100 * ((@currentTime - @startTime) / @duration)
		progressText = string.format("%d%%", progress)
		window_w, window_h = mp.get_osd_size()
		ass = assdraw.ass_new()
		ass\new_event()
		self\setup_text(ass)
		ass\append("Encoding (#{bold(progressText)})\\N")
		mp.set_osd_ass(window_w, window_h, ass.text)

	parseLine: (line) =>
		matchTime = string.match(line, "Encode time[-]pos: ([0-9.]+)")
		matchExit = string.match(line, "Exiting... [(]([%a ]+)[)]")
		if matchTime == nil and matchExit == nil
			return
		
		if matchTime != nil and tonumber(matchTime) > @currentTime -- sometimes we get timestamps older than before...
			@currentTime = tonumber(matchTime)
		if matchExit != nil
			@finished = true
			@finishedReason = matchExit
	
	runAndReadLinesAsync: (command_line, line_callback, finish_callback) => nil

	onLine: (line) =>
		self\parseLine(line)
		self\draw!

	startEncode: (command_line, finish_callback) =>
		copy_command_line = [arg for arg in *command_line]
		append(copy_command_line, { '--term-status-msg=Encode time-pos: ${=time-pos}\\n' })
		self\show!
		self\runAndReadLinesAsync(copy_command_line, self\onLine, () ->
			self\hide!

			-- This is what we want
			if @finishedReason == "End of file"
				finish_callback(true)
			else
				finish_callback(false)
		)

class PopenEncodeWithProgress extends BaseEncodeWithProgress
	runAndReadLinesAsync: (command_line, line_callback, finish_callback) =>
		processFd = run_subprocess_popen(command_line)
		for line in processFd\lines()
			msg.verbose(string.format('%q', line))
			line_callback(line)
		processFd\close()

		finish_callback!

class WindowsEncodeWithProgress extends BaseEncodeWithProgress
	runAndReadLinesAsync: (command_line, line_callback, finish_callback) =>
		subprocess_helper_command_line = {
			-- Assume that, if we reached this point, this won't return nil.
			find_subprocess_helper!,
			mp.get_property("input-ipc-server"),
			mp.get_script_name()
		}
		append(subprocess_helper_command_line, command_line)
		msg.verbose("WindowsEncodeWithProcess: command line: #{utils.to_string(subprocess_helper_command_line)}")
		mp.register_script_message("process-line", line_callback)
		mp.command_native_async({
			name: "subprocess",
			args: subprocess_helper_command_line,
			playback_only: false
		}, (res, result, err) ->
			if not res
				msg.verbose("Command line failed! Error string: #{err}, #{utils.to_string(result)}, #{utils.to_string(res)}")
			
			finish_callback(res)
		)
