
# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64

	# Erase missiles by replacing with space
	EMPTY = 32 
	# Save screen width of 80 as a constant for setting pixel index before mp1_poke
	screen_width = 80

# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
prev:				.long 0x0	# address of previous missile (used for removing nodes from LL)
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs
	# Width of screen (80 pixels)
oldpos_x:			.long 0x0	# old x position
oldpos_y:			.long 0x0	# old y position
city_start:			.long 1938	# leftmost index of base centered at x = 20 (18,24) -- pixel 1938 x 2 char per pixel

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb	%cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks: TODO redraw cities, redraw crosshairs	
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
	#SCRATCH

	#SCRATCH
	pushl	%ebp			# Modify stack pointer, save ebp
	movl 	%esp, %ebp		
							# Save callee-saved registers
	pushl	%ebx			
	pushl	%esi
	pushl	%edi
							
	pushl	%edx			# Save caller-saved registers						
	pushl	%ecx					
	pushl 	%eax	
	call update_missiles	# 1. Update missiles
	popl	%eax			# Restore caller-saved registers
	popl	%ecx
	popl	%edx

	pushl	%edx			# Save caller-saved registers						
	pushl	%ecx					
	pushl 	%eax	
	call redraw_cities		# 2. Redraw cities
	popl	%eax			# Restore caller-saved registers
	popl	%ecx
	popl	%edx

	pushl	%edx			# Save caller-saved registers						
	pushl	%ecx					
	pushl 	%eax	
	call redraw_crosshair	# 3. Redraw crosshairs
	popl	%eax			# Restore caller-saved registers
	popl	%ecx
	popl	%edx

	popl	%edi			# Restore callee-saved registers
	popl	%esi	
	popl	%ebx
	

	# Restore stack/bottom pointer
	leave		
	ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl

mp1_ioctl:	
		pushl	%ebp				# Modify stack pointer, save ebp
		movl 	%esp, %ebp	
		pushl	%ebx				# save callee-saved registers. These will be restored after ioctl_cmd# finishes.
		pushl	%esi
		pushl	%edi
		movl 	12(%ebp), %ebx 		# load value of cmd into ebx
		movl	8(%ebp), %esi		# load value of arg into esi
		cmpl	$0, %ebx			# Only 0 <= cmd <= 4 are valid. Confirm this by checking ebx.
		jl		cmd_invalid			
		cmpl	$4, %ebx			
		jg		cmd_invalid				
		jmp		*jump_table(, %ebx, 4)	# jump to specified ioctl function

cmd_invalid:
		popl	%edi				# Restore callee-saved registers
		popl	%esi	
		popl	%ebx
		movl	$-1, %eax			# set return value (eax) to -1
		leave
		ret							# 

jump_table:
.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame

# ----------------- Functions private to this file -------------------

#----------------------------------------------------------------------------------------------------------------------------
# Interface: Missile data is placed in struct in linked list
#    Inputs: None -- this function uses variables stored in memory.
#            
#   Outputs: Updates/changes all missiles according to current status
# Registers: May clobber caller-saved registers

update_missiles: 					#part 1 of mp1_rtc_tasklet
	
	# Register Use:
	# eax 	points to the current missile: NEXT(%eax) = (%eax) = &(curr->next))
	# ebx 	is used as a temporary register
	# ecx 	(cl) will hold the character to be drawn with mp1_poke
	# edx 	stores the previous node's address 
	# esi 	holds X coordinate of current missile
	# edi 	holds Y coordinate of current missile
	
	# Notes:
	# old x-coordinates are stored in memory at oldpos_x and oldpos_y
		pushl	%ebp
		movl 	%esp, %ebp

		pushl	%ebx					# save callee-saved registers. These will be restored after ioctl_cmd# finishes.
		pushl	%esi
		pushl	%edi
							
		movl	mp1_missile_list, %eax  # move head of missile list into eax (eax= &first node)
		xorl	%edx, %edx				# set edx to 0 (prev = NULL)

	start:	
				
		cmpl	$0, %eax				# check to make sure eax != 0 (NULL) before dereferencing
		jz		update_done				# if curr == NULL, we're done.	
		movl	X(%eax), %esi			# Move (x,y) into esi and edi
		movl	Y(%eax), %edi	
		cmpl	$0, EXPLODED(%eax)		# Check exploded against 0
		jne		exploding				# If exploding (exploded != 0), skip position update stuff
										
										# If NOT exploding:
		movl	%esi, oldpos_x			# Store current x as old X
		movl	%edi, oldpos_y			# store current y as old Y
		addl	VX(%eax), %esi			# X += VX (Update x and y)
		addl	VY(%eax), %edi			# Y += VY
		movl	%esi, X(%eax)			# update coordinates in missile struct
		movl	%edi, Y(%eax)

										# Case 1: Check if missile has moved off the screen
		movl	%esi, %ebx				# convert X from "game coordinates" to screen coordinates (shift right 16)
		shr		$16, %ebx				# 
		cmpl	$80, %ebx				# 
		jge		out_of_bounds			# remove the missile if x >= 80
		cmpl	$0, %ebx				# 
		jl		out_of_bounds			# remove missile if x < 0
		jmp		check_missile_y

	check_missile_y:
		movl	%edi, %ebx				# convert Y from "game coordinates" to screen coordinates (shift right by 16 places)
		shr		$16, %ebx				# 
		cmpl	$25, %ebx				# 
		jge		out_of_bounds			# remove the missile if y >= 25
		cmpl	$0, %ebx				# 
		jl		out_of_bounds			# remove missile if y < 0
		jmp		check_destination

	out_of_bounds:
		pushl	%edx					# save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax	
		call	mp1_missile_remove		# remove missile
		popl	%ecx					# restore caller-saved regs (discard old eax -- its memory has been deallocated).
		popl	%ecx					
		popl	%ecx					# discard old edx as it has been updated in mp1_missile_remove
		cmpl	$0, %eax
		je		update_done
		jmp		start

	check_destination:					# Case 2: Missile is at destination/exploding. Having passed case 1, we know at this point that the missile/explosion must be on screen
		
		movl	%esi, %ebx				# get x coordinates of missile
		shr		$16, %ebx				# convert to screen coords
		cmpl	DEST_X(%eax), %ebx		# Check x-position against destination
		jne		mp1_missile_redraw		# If it's not at the destination, draw missile on screen.			
		movl	%edi, %ebx				# get y coordinates of missile
		shr		$16, %ebx				# convert to screen coords
		cmpl	DEST_Y(%eax), %ebx		# Check y-position against destination		
		jne		mp1_missile_redraw		# If it's not at the destination, draw missile on screen.				
										
										# erase the missile from its old position if we're at the destination.
		pushl	%edx					# save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax
		movb	$EMPTY, %cl				# Set cl to " " to erase missile at current position.
		movl	$screen_width, %eax		# eax = 80
		movl	oldpos_y, %ebx			
		shr		$16, %ebx				# convert to screen coords
		mull	%ebx					# edx:eax = $screen_width * old_y
		movl	oldpos_x, %ebx	
		shr		$16, %ebx				# convert to game coords
		addl	%ebx, %eax				# eax = pixel number
		addl	%eax, %eax				# 2 char per index
		call	mp1_poke
		popl	%eax					# restore caller-saved regs
		popl	%ecx					
		popl	%edx
		
	exploding:
		
		pushl	%edx					# save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax					# push arg eax last (eax contains pointer to missile)
		call 	missile_explode			# note caller-save regs popped at decrement_explosion
		cmpl	$0, %eax				# check return value (missile explode)
		je		decrement_explosion		# if no events occured (eax = 0), skip notification.
		popl	%eax					# restore caller-saved regs
		popl	%ecx					
		popl	%edx

		pushl	%edx					# prepare to call notify_user: save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax					
		call	mp1_notify_user			
	
	decrement_explosion:				# 1. Decrement EXPLODED, 2. Check if EXPLODED is 0	
		popl	%eax					# restore caller-saved regs
		popl	%ecx					
		popl	%edx
		
		decl	EXPLODED(%eax)			# Decrement missile.exploded
		cmpl	$0, EXPLODED(%eax)		# Is the missile done exploding?	
		je		explode_over			# It it is, get rid of it.
										
		movb	$EXPLOSION, %cl			# move explosion into cl: "@"	
		
		pushl	%edx					# save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax
		movl	$screen_width, %eax		# Set pixel index for mp1_poke
		movl	%edi, %ebx				
		shr		$16, %ebx				# Shift right to convert to screen coords.
		mull	%ebx					
		movl	%esi, %ebx
		shr		$16, %ebx				# Shift right to convert to screen coords.
		addl	%ebx, %eax				
		addl	%eax, %eax				
		call	mp1_poke				# print to screen (eax = index, cl = char)
		popl	%eax					# restore caller-saved regs
		popl	%ecx					
		popl	%edx
		jmp 	next
		
	explode_over:	
		pushl	%edx					# save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax
		movb	$EMPTY, %cl				# set cl to " "
		movl	X(%eax), %esi			# esi = x
		movl	Y(%eax), %edi			# edi = y
		movl	$screen_width, %eax		# set pixel index for mp1_poke
		movl	%edi, %ebx				
		shr		$16, %ebx				# Shift right to convert to screen coords.
		mull	%ebx					
		movl	%esi, %ebx
		shr		$16, %ebx				# Shift right to convert to screen coords.
		addl	%ebx, %eax				
		addl	%eax, %eax				
		call	mp1_poke				# print to screen (eax = index, cl = char)
		popl	%eax					# restore caller-saved regs
		popl	%ecx					
		popl	%edx
		
		pushl	%edx					# save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax
		call	mp1_missile_remove		# remove missile
		popl	%ecx					# restore caller-saved regs (discard old eax -- its memory has been deallocated).
		popl	%ecx					
		popl	%ecx					# discard old edx as it has been updated in mp1_missile_remove
		cmpl	$0, %eax
		je		update_done
		jmp		start					# process the new missile

										# Case 3: Missile is moving on screen (and isn't exploding)
	mp1_missile_redraw:					# 1. Erase at old position, 2. Redraw at new position									
		pushl	%edx					# save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax
		movb	$EMPTY, %cl				# Set cl to " " to erase missile at current position.
		movl	$screen_width, %eax		
		movl	oldpos_y, %ebx			
		shr		$16, %ebx				# convert to screen coords
		mull	%ebx					
		movl	oldpos_x, %ebx	
		shr		$16, %ebx				# convert to screen coords
		addl	%ebx, %eax				
		addl	%eax, %eax				
		call	mp1_poke				# print to screen
		popl	%eax					# restore caller-saved regs
		popl	%ecx					
		popl	%edx
										# Redraw
		movb	C(%eax), %cl			# move missile character to %cl to redraw missile
		
		pushl	%edx					# save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax
		movl	$screen_width, %eax		# set correct index for pixel
		movl	%edi, %ebx				
		shr		$16, %ebx				
		mull	%ebx					
		movl	%esi, %ebx
		shr		$16, %ebx				# convert x to screen coordinates and add to index 
		addl	%ebx, %eax				
		addl	%eax, %eax				
		call	mp1_poke				# print to screen
		popl	%eax					# restore caller-saved regs
		popl	%ecx					
		popl	%edx
		jmp 	next					

	next:
		movl	%eax, %edx				# update previous node (prev = curr)
		cmpl	$0, %eax
		je 		update_done
		movl	NEXT(%eax), %ebx		# move to next missile in the list (curr = curr->next)
		movl	%ebx, %eax				
		jmp 	start					# update the next missile!

	update_done:
		popl	%edi					# Restore callee-saved registers
		popl	%esi	
		popl	%ebx
		
		leave
		ret								# return - function complete.
#----------------------------------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------------------------------
# Interface: Arguments are set in registers before calling function
#    Inputs: eax - current node in linked list -- ie. missile to be deleted
#			 edx - previous node in linked list
#   Outputs: After execution, eax and edx will be curr and prev of newly updated linked list.
# Registers: eax (curr) and edx (prev) are changed to reflect newly updated linked list	
#			 Clobbers ecx.

mp1_missile_remove:						# This function updates the linked list before deallocating the missile's memory.
										# 1. Erase missile from screen, 
										# 2. Remove missile from linked list, 
										# 3. Deallocate missile memory
										# Helper function for update missile
										# eax holds the address of the missile to be deleted
										
		pushl	%ebp					# Modify stack pointer, save ebp
		movl 	%esp, %ebp		
		
		pushl	%ebx					# save callee-saved registers
		pushl	%esi
		pushl	%edi

		pushl	%edx					# save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax	

		movb	$EMPTY, %cl				# ERASE old position Set cl to " ". 
		movl	$screen_width, %eax		# eax = 80
		movl	oldpos_y, %ebx			# 
		shr		$16, %ebx				# convert to screen coords
		mull	%ebx					# edx:eax = $screen_width * old_y
		movl	oldpos_x, %ebx			# 
		shr		$16, %ebx				# convert to screen coords
		addl	%ebx, %eax				# eax += old_x	<- eax = index
		addl	%eax, %eax
		call	mp1_poke
		popl	%eax					# restore caller-saved regs
		popl	%ecx					
		popl	%edx	
										# REMOVE missile from linked list
		cmpl	$0, %edx				# If previous (edx) is NULL, then that means we are removing the first node. (prev == NULL)
		je		update_head				# 
		movl	NEXT(%eax), %ebx		# Set prev->next = curr->next
		movl	%ebx, NEXT(%edx)		# 
		movl	%eax, %ecx				# ecx holds the pointer to be freed
		movl	%ebx, %eax				# eax becomes eax->next
	free_missile:						# FREE		
		pushl	%edx					# prepare to call: save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax					
		push	%ecx					# push arg ecx
		call 	mp1_free				# free current missile
		popl	%ecx
		popl	%eax					# restore caller-saved regs
		popl	%ecx					
		popl	%edx
		jmp		remove_done				# move to next missile.

	update_head:	

		movl 	NEXT(%eax), %ebx		# ebx = missile.NEXT
		movl	%ebx, mp1_missile_list	# so we'll need to update mp1_missile_list to point to missile.NEXT instead of prev->NEXT
		jmp		free_missile	

	remove_done:
		popl	%edi					# Restore callee-saved registers
		popl	%esi	
		popl	%ebx

		leave
		ret
#----------------------------------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------------------------------
# Interface: Data is stored in memory before function is called
#    Inputs: Variables base_alive, dead_base_pic and base_pic
#   Outputs: Cities are redrawn on screen based on current status
# Registers: See register use below. May clobber caller-saved registers eax, edx, ecx.

redraw_cities: 						# Part 2 of mp1_rtc_tasklet

	# Register Use:
	# eax - holds pixel index
	# ebx - temp reg/holds a copy of string to be printed (in cl)
	# ecx - holds character to be output to display
	# edx - holds base_alive and is referenced to determine status of each city
	# esi - offset for which character in the base to draw/which pixel to draw it in
	# edi - offset based on which base we're drawing

		pushl	%ebp				# Modify stack pointer, save ebp
		movl 	%esp, %ebp		
									
		pushl	%ebx				# save callee-saved registerss
		pushl	%esi
		pushl	%edi

		movl	$0, %edi			# Set base offset to 0 
		
		movl	base_alive, %edx	# put base_alive into %edx so we can look at the bits

	next_city:
		movl	$0, %esi			# Set counter esi to 0 (for first character)
		movl	city_start, %eax	# Initialize Registers
		addl	%edi, %eax			# Add base offset to pixel index
		addl	%esi, %eax			# Add character offset to pixel index
		addl	%eax, %eax			# 2 characters per pixel
		
	next_character:

		cmpb	$0, %dl				# Check if base is alive/dead by looking at lowest byte of edx
		jne		live_city			# Draw a live city if base_alive != 0 for the current city						
	
	dead_city:						# Dead city
		leal	dead_base_pic, %ebx	# Load address of dead_base into ebx
		movb	(%ebx, %esi), %cl  	# Load string[esi] into cl
		jmp		draw_character		# with eax = index and cl = char, output to screen.
		
	live_city:	
		leal	base_pic, %ebx 		# Load address of base_pic into ebx
		movb	(%ebx, %esi), %cl  	# Load string[esi] into cl. We're ready to ouput now.

	draw_character:
		pushl	%edx				# save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax	

		call	mp1_poke			# Draw to screen
	
		popl	%eax				# Restore caller-saved registers
		popl	%ecx
		popl	%edx
									# PREPARE TO DRAW NEXT CHAR/CITY
		addl	$2,	%eax			# increase index in preparation to draw to next pixel	
		addl	$1, %esi			# increment counter esi
		cmpl	$5, %esi			# if offset is 5, we're done printing this city.
		jne		next_character		# if we're not done drawing the city, move to next char.

		shr 	$8, %edx			# get ready to at the next byte in base_alive (status of next city)
		addl	$20, %edi			# Add 20 pixels (40 bytes) to base_offset in preparation to draw the next base
		cmpl	$60, %edi			# If offset is 60, we're done because it means we've drawn 3 cities already.
		je		cities_done	
		jmp 	next_city			

	cities_done:					# Restore registers
		popl	%edi				# Restore callee-saved registers
		popl	%esi	
		popl	%ebx

		leave
		ret
#----------------------------------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------------------------------
# Interface: Uses variables/lables stored in memory
#    Inputs: Variables crosshairs_x, crosshairs_y
#   Outputs: crosshair in new position, with old position erased
# Registers: May clobber caller saved registers. See comments immediately below.

redraw_crosshair:					#part 3 of mp1_rtc_tasklet

	# Register Use:
	# eax - pixel index for mp1_poke(will also hold crosshair X during compute process)
	# ebx - crosshair Y
	# ecx - crosshair character (cl)
	# edx - screen width (80)
	# esi - temporary/not used
	# edi - temporary/not used
		pushl	%ebp			# Modify stack pointer, save ebp
		movl 	%esp, %ebp		

		pushl	%ebx				# save callee-saved registers
		pushl	%esi
		pushl	%edi							

		pushl	%edx				# save caller-saved regs before mp1_poke								
		pushl	%ecx					
		pushl 	%eax				# 
		movl	crosshairs_y, %eax	# Load crosshair coordinates
		movl	crosshairs_x, %ebx	# 
		movb	$43, %cl			# Load crosshair character (43) to cl. eax = index, cl = "+"
		movl	$80, %edx			# Set index for mp1_poke
		mull	%edx				# 
		addl	%ebx, %eax			# 
		addl	%eax, %eax			# 2 char per index
		call	mp1_poke			# Output to screen
		popl	%eax				# restore caller-saved regs after mp1_poke
		popl	%ecx					
		popl	%edx
										
		popl	%edi				# Restore callee-saved registers
		popl	%esi	
		popl	%ebx
		
		leave
		ret
#----------------------------------------------------------------------------------------------------------------------------
# IOCTLs start below
#
#
#
#----------------------------------------------------------------------------------------------------------------------------
# Interface: No argument -- called by passing cmd # and calling mp1_ioctl
#    Inputs: None
#   Outputs: Returns 0 upon starting the game
# Registers: Does not clobber registers
mp1_ioctl_startgame:				# TODO init variables
									# set all bases to alive
		
		#edi used as a temporary register
		#eax holds return value
		
		movl	$0, %edi
		addl	$1, %edi			# base 1 = alive	
		shl		$8, %edi
		addl	$1, %edi			# base 2 = alive
		shl		$8, %edi
		addl	$1, %edi			# base 3 = alive
		movl	%edi, base_alive	# move this into base_alive
		
		movl	$0, mp1_score		# initialize score to 0
									
		movl	$40, crosshairs_x	# set crosshairs to (40, 12)
		movl	$12, crosshairs_y
		
		popl	%edi				# Restore callee-saved registers
		popl	%esi	
		popl	%ebx
		movl	$0, %eax			#return 0
		leave
		ret
#----------------------------------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------------------------------
# Interface: Register esi holds argument
#    Inputs: register esi
#   Outputs: Adds new missile to linked list. Returns 0 in eax if successful, -1 if not. 
# Registers: may clobber caller saved registers. See summary of register use below:

mp1_ioctl_addmissile:

	# Register Use:
	# eax 	holds function return values and the memory address to add the missile to
	# ebx	temporary variable
	# esi 	holds user space pointer
	

		pushl	%edx				# save caller-saved regs								
		pushl	%ecx	
		pushl	%eax
		movl	$36, %ebx			# size of missile = (4 + 2*4 + 2*4 + 2*4 + 4 + 1) + 3(for alignment) = 36 bytes
		
		pushl 	%ebx				# push ebx as argument to malloc
		call 	mp1_malloc			# allocate memory. eax holds the pointer now
		cmpl	$0, %eax			# did malloc return NULL? if so, leave.
		je		addmissile_leave	
		popl	%ebx				# pop arg ebx
		
		popl	%ecx				# restore caller-saved registers after calling malloc
		popl	%ecx				# don't pop back into eax because it holds the ptr to memory
		popl	%edx
									# move missile info into kernel memory (copy_from_user)
		pushl	%edx				# save caller-saved regs								
		pushl	%ecx	
		pushl	%eax

		pushl	%ebx				# push args: 1) n = 36 = ebx
		pushl	%esi				# push 2) source (from)
		pushl	%eax				# push 3) destination (to)
		call	mp1_copy_from_user	# eax contains # of unallocated bits
		cmpl	$0, %eax 			# check for unallocated bits
		jne		addmissile_invalid	# if eax != 0, something bad happened								
									# missile is now ready to be added to front of LL
		popl	%eax				# get args off the stack
		popl	%esi				
		popl	%ebx

		popl	%eax				# restore caller-saved registers after calling malloc
		popl	%ecx				
		popl	%edx

		movl	mp1_missile_list, %ebx 	# set missile's next to 1st missile on list
		movl	%ebx, NEXT(%eax)		
		movl	%eax, mp1_missile_list	# new missile becomes head

		jmp		addmissile_leave	# leave	function

	addmissile_invalid:

		call	mp1_free			#de-allocate memory before leaving

		popl	%eax				# get args off the stack
		popl	%esi				
		popl	%ebx

		popl	%eax				#restore caller-saved registers from function start
		popl	%ecx				
		popl	%edx
		
		popl	%edi				# Restore callee-saved registers from dispatcher
		popl	%esi	
		popl	%ebx
		movl	$-1, %eax			# return -1 (overwrites restore)
		leave 
		ret
	addmissile_leave:
		
		popl	%edi				# Restore callee-saved registers from dispatcher
		popl	%esi	
		popl	%ebx
		movl	$0, %eax			# return 0
		leave
		ret
#----------------------------------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------------------------------
# Interface: Argument passed with esi.
#    Inputs: Variables crosshairs_x and crosshairs_y
#   Outputs: Returns 0 upon updating crosshair in response to user input. Does not fail.
# Registers: May clobber caller-saved registers.

mp1_ioctl_movexhairs:				
		# ecx and esi will contain +x and +y components
		# They will later contain unclipped x, y coordinates
		
		movw	%si, %cx			# put esi into ecx to obtain +x
		
		shr 	$16, %esi  			# shift esi right 16 times to obtain +y
		
	add_coordinates:
		movl	crosshairs_y, %eax  # hold old coordinates in eax and ebx
		movl	crosshairs_x, %ebx	
		addw	crosshairs_x, %cx	# compute new coordinates for x, y
		addw	crosshairs_y, %si	# 
		
		cmpw	$80, %cx			# clip coordinates if necessary				
		jge		clip_x_max			
		cmpw	$0, %cx	
		jge		check_y				# if x looks good (x >= 0, < 80), check y.	
		jl		clip_x_min

	clip_x_max:
		movw	$79, %cx
		jmp		check_y
	clip_x_min:
		movw	$0, %cx
	
	check_y:						# check upper and lower bounds of y coordinate
		cmpw	$25, %si
		jge		clip_y_max
		cmpw	$0, %si
		jge		update_xhaircoord
		jl		clip_y_min
		
	clip_y_max:
		movw	$24, %si
		jmp		update_xhaircoord
	clip_y_min:
		movw	$0, %si
	
	update_xhaircoord:				#save clipped coordinates
		movw	%cx, crosshairs_x
		movw	%si, crosshairs_y
		
	erase_redraw_xhair:
		
		pushl	%edx			# Save caller-saved registers						
		pushl	%ecx					
		pushl 	%eax		
		movl	$80, %edi
		mull	%edi			# eax = old_y*$screen_width 
		addl	%ebx, %eax		# eax = row index + col index
		addl	%eax, %eax		# eax = 2 char per pix
		movl	$EMPTY, %ecx	# put " " in cl
		call	mp1_poke		# erase old crosshair
		popl	%eax			# Restore caller-saved registers
		popl	%ecx
		popl	%edx
		
		pushl	%edx			# Save caller-saved registers						
		pushl	%ecx					
		pushl 	%eax
		call	redraw_crosshair #draw new crosshair	
		popl	%eax			# Restore caller-saved registers
		popl	%ecx
		popl	%edx

	move_xhairs_done:
		# return 0 and leave
		popl	%edi				# Restore callee-saved registers
		popl	%esi	
		popl	%ebx
		movl	$0, %eax
		leave
		ret
#----------------------------------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------------------------------
# Interface: Argument passed through register esi.
#    Inputs: Variables mp1_score and base_alive and esi
#   Outputs: Returns 0 in eax upon successfully copying status to user program, -1 if not successful
# Registers: May clobber caller-saved registers.

mp1_ioctl_getstatus:	
									# esi holds ptr user_status
									# ebx holds a copy of base_alive and later holds ptr "from"
									# eax holds the pointer to an allocated chunk of memory so we can copy_to_user
									# edi holds the status/score integer while it's being constructed
									# ecx holds score
									# edx is a counter
									# copy status of each city into bits 16-18 (0-2) from base_alive 
		movl	mp1_score, %ecx		# put score into ecx 
		movl	$0, %edi			# initialize status register to 0
		movl	base_alive, %ebx	# edi = XCCC
		
		movl	$3,	%edx			# number of cities l	eft to check
	city_status:
							
		cmpb	$0, %bl				# check lowest 8 bits of edi (base ailve)
		jne		status_alive		#
		
		shl		$1,	%edi			# If city is dead, just shift without adding 1
		jmp		next_city_status
		
	status_alive:
		addl	$1, %edi
		shl		$1, %edi

	next_city_status:
		shr 	$8, %ebx			# shift over to next city
		decl	%edx
		cmpl	$0, %edx			# 
		jg		city_status
	city_status_done:	
		shl		$15, %edi			# shift left 15 more times to clear low bits for score and shift city status into correct pos.
		movw	%cx, %di			# put score in lower 16 bits of ebx
		
		pushl	%edx				# save caller-saved regs except eax	(return value)						
		pushl	%ecx	
		
		pushl	$4					# we need 4 bytes
		call 	mp1_malloc			# allocate memory. eax holds the pointer now
		popl	%ecx				# pop arg (don't care if value is lost)
		popl	%ecx				# Restore caller-saved registers (eax not incl.)		
		popl	%edx
		cmpl	$0, %eax
		je		status_malloc_invalid
		
		
		movl	%edi, (%eax)		# put info into newly allocated memory
		
		
		pushl	%edx				# save caller-saved regs								
		pushl	%ecx	
		pushl	%eax
		
		pushl	$4					# push n = 4
		pushl	%eax				# push from = eax
		pushl	%esi				# push to = esi
		call	mp1_copy_to_user	# copy the information to user space
		cmpl	$0, %eax			# check return value
		jne		get_status_invalid	# copy failed. Return -1
		popl	%esi				# pop args from copy_to_user, 
		popl	%eax				# pop n = 4 from stack into eax,
		popl	%eax				# which will be overwritten by subsequent pops
		
		popl	%eax				# Restore caller-saved registers # eax = ptr
		popl	%ecx
		popl	%edx
		
		pushl	%edx				# save caller-saved regs								
		pushl	%ecx	
		pushl	%eax
		
		call	mp1_free			# deallocate memory after copying to avoid a memory leak
		

		popl	%eax				# Restore caller-saved registers
		popl	%ecx
		popl	%edx
		
		movl	$0, %eax			# return 0.
		jmp		get_status_done

	get_status_invalid:
		popl	%esi				# pop args from copy_to_user, 
		popl	%eax				# pop n = 4 from stack into eax,
		popl	%eax				# which will be overwritten by subsequent pops
		
		popl	%eax				# Restore caller-saved registers # eax = ptr
		popl	%ecx
		popl	%edx
		
		pushl	%edx				# save caller-saved regs								
		pushl	%ecx	
		pushl	%eax
		call	mp1_free			#deallocate memory to avoid a memory leak
		popl	%eax				# Restore caller-saved registers
		popl	%ecx
		popl	%edx
	status_malloc_invalid:
		movl	$-1, %eax			# return -1.
	get_status_done:
		popl	%edi				# Restore callee-saved registers
		popl	%esi	
		popl	%ebx
		leave
		ret
#----------------------------------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------------------------------
# Interface: No arguments.
#    Inputs: mp1_missile_list -- head of missile linked list
#   Outputs: Returns 0 upon cleaning up the game.
# Registers: may clobber caller-saved registers

mp1_ioctl_endgame:
		
		#esi will contain head pointer
		#eax will contain the address of the current node and later the return value
		#ebx/ecx/edx are temporary registers

		movl	mp1_missile_list, %esi
										
	remove_next_missile:				# iteratively remove and free missiles from list
		movl	%esi, %eax				# eax = first missile in list
		cmpl	$0, %eax				# curr == NULL?
		je		endgame_done			# if curr == NULL, we're done.
		movl	NEXT(%eax), %esi		# missiles.head = old_head.next
		movl	$0, NEXT(%eax)			# set curr->next to null just in case.
		
		pushl	%edx					# save caller-saved regs/push arg								
		pushl	%ecx	
		pushl	%eax				
		call	mp1_free				# free missile (delete old_head/curr)
		popl	%eax					# Restore caller-saved registers
		popl	%ecx
		popl	%edx	
		jmp		remove_next_missile		# go get the next missile

	endgame_done:
		movl	$0, mp1_missile_list	# set head to null (0x0) to avoid dangling ptrs
		popl	%edi					# Restore callee-saved registers from mp1_ioctl
		popl	%esi	
		popl	%ebx
		movl 	$0, %eax				# return 0 once done
		leave
		ret
#----------------------------------------------------------------------------------------------------------------------------
