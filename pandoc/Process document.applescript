-- A script to take the front document in the frontmost application and have pandoc process it.

global ottfile, dotmfile, appName

on run
	
	-- Some stuff to make it easier to debug this script
	tell application "Finder"
		try
			if (name of processes as string) contains "AppleScript Editor" then set the visible of process "AppleScript Editor" to false
		end try
	end tell
	
	-- Set some variables for use later on
	set ASmethod to false
	set validFile to false
	set ext to ""
	set hasext to false
	set fname to ""
	set fpath to ""
	set outputfile to ""
	
	-- Some needed paths
	set myHome to POSIX path of (path to home folder)
	set myDocs to POSIX path of (path to documents folder)
	set myLib to POSIX path of (path to library folder from user domain)
	
	-- For pandoc
	-- Use single-quoted form of POSIX path
	set bibfile to "'" & myDocs & "My Library.bib'"
	
	-- These are the default templates for the output. Use unquoted forms of the POSIX path.
	set ottfile to myLib & "Application Support/LibreOffice/4/user/template/Butterick 11.ott"
	set dotmfile to myLib & "Application Support/Microsoft/Office/User Templates/Normal.dotm"
	
	-- default output-file extension without leading dot
	set outputext to "html"
	
	--Variable for reveal slideshows. Use  "--variable revealjs-url=http://lab.hakim.se/reveal-js" if local reveal.js is lacking.
	set revealConfig to "-i -V theme=sky -V transition=convex -V transitionSpeed=slow -V revealjs-url=/Users/john_muccigrosso/Documents/github/cloned/reveal.js/ "
	
	-- More variables
	set pandocSwitches to "-s -S --self-contained --columns 800 --bibliography=" & bibfile & " --latex-engine=xelatex "
	
	
	
	tell application "System Events"
		try
			set appName to (the name of every process whose frontmost is true) as string
		on error errMsg
			display alert "Problem" message "Could not get the name of the frontmost application."
		end try
	end tell
	
	--Wrapping the whole thing in this tell to keep error messages in the application (not sure this is necessary)
	tell application appName
		-- Get info for frontmost window
		-- The first part won't ever work for MacDown because it doesn't do applescript, but maybe someday.
		activate
		try
			set fpath to (path of document 1) as text
			set fname to (name of document 1) as text
			set ASmethod to true
		on error
			try
				tell application "System Events" to tell (process 1 where name is appName)
					--Not sure why, but the following is needed with certain apps (e.g., BBEdit 8)
					activate
					set fpath to value of attribute "AXDocument" of window 1
					set fname to value of attribute "AXTitle" of window 1
				end tell
			on error errMsg
				-- Something went wrong.
				display alert "Can't get file" message "Can't get info on the frontmost document." buttons {"OK"} giving up after 30
				error -128
			end try
		end try
		-- When the document hasn't been saved, fpath gets assigned "" or "missing value", depending on the method used above.
		if fpath is missing value or fpath = "" then
			display alert "Unsaved document" message "The frontmost document appears to be unsaved. Please save it with an extension of \"md\" or \"markdown\" before trying again." buttons "OK" default button 1
			error "Unsaved document"
		else
			if not ASmethod then
				-- fpath got assigned by second method and needs to be converted into a real posix path.
				-- Second substitution needed because of varying form of fpath value from BBEdit 8. Could be outdated.
				set fpath to do shell script "x=" & quoted form of fpath & "
        				x=${x/#file:\\/\\/}
        				x=${x/#localhost}
        				printf ${x//%/\\\\x}"
			end if
		end if
		-- We got a file path, now make sure it's a markdown file, based on the file extension, checking if there is one.
		try
			set ext to my get_ext(POSIX file fpath as alias as string)
		on error
			set fname to ""
		end try
		set hasext to (length of ext > 0)
		if ext = "md" or ext = "markdown" then set validFile to true
		
		if fname � "" and not validFile then
			set alertResult to display alert "Not markdown" as warning message �
				"The file doesn't appear to be in markdown format. Proceed anyway?" buttons {"Yes", "No"} default button 2 giving up after 30
			if button returned of alertResult = "Yes" then
				set validFile to true
			end if
		end if
		
		if validFile then
			
			-- Run the pandoc command using the path we found.
			
			--TO-DO: Let the user choose the output filetype.
			
			set outputfn to fname
			-- Strip the extension when it exists
			if hasext then
				repeat with i from 1 to (number of characters in ext) + 1
					set fname to characters 1 through ((length of fname) - 1) of fname as string
				end repeat
			end if
			-- And then add the new extension
			--    Check for ridiculously long filename
			if length of fname > 251 then set fname to characters 1 thru 251 of fname as string
			set fname to fname & "." & outputext
			repeat until outputfile � ""
				try
					set outputfile to choose file name default name fname default location fpath with prompt "Select location for output:"
					-- Make sure it's got an extension or pandoc won't know what to do with it
					set tid to AppleScript's text item delimiters
					set AppleScript's text item delimiters to ":"
					set outputname to the last text item of (outputfile as string)
					set AppleScript's text item delimiters to tid
					--if outputname does not contain "." then error "no extension"
					if length of (my get_ext(outputname)) = 0 then error "no extension"
					
					--TO-DO: Let the user choose whether to open output file once created. Checkbox in output-file dialog box?
					
					-- Get any special switches the user wants to add
					try
						set dialogResult to (display dialog "Enter any special pandoc switches here:" default answer "" buttons {"Cancel", "Never mind", "OK"} default button 3)
						if the button returned of dialogResult is "OK" then
							set pandocUserSwitches to the text returned of dialogResult & " "
							if pandocUserSwitches contains "revealjs" then set pandocSwitches to pandocSwitches & revealConfig
						else
							error (the button returned of dialogResult)
						end if
					on error errMsg
						if errMsg = appName & " got an error: User canceled." then
							exit repeat -- drop out of the repeat loop and thus the script
						end if
						-- else the button returned is "Never mind"
						set pandocUserSwitches to ""
					end try
					-- Set template for pandoc.
					set refFile to my set_refFile(outputfile)
					-- Change to POSIX form
					set outputfile to quoted form of POSIX path of outputfile & " "
					
					-- Create shell script for pandoc
					--	First have to reset PATH to use homebrew binaries and find xelatex; there are other approaches to this problem.
					set shcmd to "export PATH=/usr/local/bin:/usr/local/sbin:/usr/texbin:$PATH; "
					--	Now add the pandoc switches based on config at top and user input.
					set shcmd to shcmd & "pandoc " & pandocSwitches & pandocUserSwitches
					
					-- Run the pandoc command & open the resulting file
					try
						do shell script shcmd & refFile & "-o " & outputfile & quoted form of fpath
						do shell script "open " & outputfile
					on error errMsg
						display alert "pandoc error" message "pandoc reported the following error:" & return & return & errMsg
					end try
				on error errMsg
					if errMsg = "no extension" then
						set alertResult to display alert "No extension" message "The filename must contain an extension, so pandoc knows what type to export it as." buttons {"Cancel", "Retry"} default button 2 cancel button 1
						set outputfile to ""
					else
						exit repeat
					end if
				end try
				
			end repeat -- output filename check
		end if -- validFile check
	end tell
end run

-- Subroutine to set the reference file switch for pandoc
-- File choice is based on ext, the file extension
-- Pad it with spaces.
on set_refFile(filename)
	try
		tell application appName
			set ext to my get_ext(filename as string)
			if ext = "odt" then
				return " --reference-odt='" & POSIX path of (choose file default location (ottfile) with prompt "Select template for odt file:" of type "org.oasis-open.opendocument.text-template") & "' "
			else
				if ext = "docx" or ext = "doc" then
					return " --reference-docx='" & POSIX path of (choose file default location (dotmfile) with prompt "Select template for Word file:" of type "org.openxmlformats.wordprocessingml.template.macroenabled") & "' "
				else
					return " "
				end if
			end if
		end tell
	on error errMsg
		display alert "Error" message "Fatal error getting reference file: " & errMsg
	end try
end set_refFile

-- Subroutine to get extension from filename
-- Assumes there is a "." in the passed filename
-- Can't use the "name extension" method because the file doesn't exist yet and we should avoid creating it
on get_ext(filename)
	try
		if filename does not contain "." then
			set ext to ""
		else
			set tid to AppleScript's text item delimiters
			set AppleScript's text item delimiters to "."
			set ext to the last text item of filename
			set AppleScript's text item delimiters to tid
		end if
		return ext
	on error errMsg
		display alert "Error" message "Fatal error getting extension of file: " & errMsg
		error -128
	end try
end get_ext