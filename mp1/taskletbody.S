update_missiles: 					#part 1 of mp1_rtc_tasklet

	#TODO: complete case 2, implement subroutine/labels, 
	
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
		movl	%eax, save_eax 			#save registers
		movl	%ebx, save_ebx
		movl	%ecx, save_ecx
		movl	%edx, save_edx
		movl	%esi, save_esi
		movl	%edi, save_edi
							
		movl	mp1_missile_list, %eax  # move head of missile list into eax (eax= &first node)
		xorl	%edx, %edx				# set edx to 0 (prev = NULL)

	start:	
				
		cmpl	$0, %eax				# check to make sure eax != 0 (NULL) before dereferencing
		jz		update_done				# if curr == NULL, we're done.	
		movl	X(%eax), %esi			# Move (x,y) into esi and edi
		movl	Y(%eax), %edi	
		cmpl	$0x0, EXPLODED(%eax)	# Check exploded against 0
		jnz		exploding				# If exploding (exploded != 0), skip position update stuff
										
										# If NOT exploding:
		movl	%esi, %ebx				# Store current x as old X
		movl	%ebx, oldpos_x
		movl	%edi, %ebx				# store current y as old Y
		movl	%ebx, oldpos_y
		addl	VX(%eax), %esi			# X += VX (Update x and y)
		addl	VY(%eax), %edi			# Y += VY

										# Case 1: Check if missile has moved off the screen
		movl	%esi, %ebx				# convert X from "game coordinates" to screen coordinates
		shr		$16, %ebx				# conversion: shift right by 16 places
		cmpl	$80, %ebx				# compare missile x-coord vs screen width (80). If x >= 80, it's out of bounds
		jl		check_destination		# don't remove the missile if it's @ x < 80
		cmpl	$-1, %ebx				# compare x-coord to -1
		jg		check_destination		# don't remove missile if x > -1

		movl	%edi, %ebx				# convert Y from "game coordinates" to screen coordinates
		shr		$16, %ebx				# shift right by 16 places
		cmpl	$25, %ebx				# compare missile y-coord vs screen width (25). If y >= 25, it's out of bounds
		jl		check_destination		# remove the missile if it's @ y >= 25
		cmpl	$-1, %ebx				# compare y-coord to -1
		jg		check_destination		# don't remove missile if y > -1

		pushl	%edx					# save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax	
		call	mp1_missile_remove		# if x < 0 or x > 79 or y < 0 or y > 24, remove the missile.
		popl	%eax					#restore caller-saved regs
		popl	%ecx
		popl	%eax

	check_destination:					# Case 2: Missile is at destination/exploding. Having passed case 1, we know at this point that the missile/explosion must be on screen
		cmpl	DEST_X(%eax), %esi		# Check x-position against destination
		jne		missile_on_screen		# If it's not at the destination, draw missile on screen.			
		cmpl	DEST_Y(%eax), %edi		# Check y-position against destination		
		jne		missile_on_screen		# If it's not at the destination, draw missile on screen.				

	exploding:							
		pushl	%edx					# save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax					# push arg eax last (eax contains pointer to missile)
		call 	missile_explode			# note caller-save regs popped at decrement_explosion
		cmpl	$0, %eax				# check return value (missile explode)
		jz		decrement_explosion		# if no events occured (RV = 0), skip notification.

		pushl	%edx					# prepare to call notify_user: save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax					# push args - eax
		call	mp1_notify_user			
		popl	%eax					# restore caller-saved regs
		popl	%ecx					
		popl	%edx
										
	decrement_explosion:				# 1. Decrement EXPLODED, 2. Check if EXPLODED is 0
		popl	%eax					# restore caller-saved regs from calling missile_explode
		popl	%ecx					
		popl	%edx
		movb	$EXPLOSION, %cl			# Preemptively move explosion into cl in case a redraw is needed.			
		subl	$1, EXPLODED(%eax)		# Decrement missile.exploded
		cmpl	$0, EXPLODED(%eax)		# is exploded == 0? (ie. is the missile done exploding?)	
		jle		redraw_exploding		# If the missile isn't done exploding, then redraw its explosion.
		pushl	%edx					# save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax
		call	mp1_missile_remove		# remove missile
		popl	%eax					# restore caller-saved regs
		popl	%ecx					
		popl	%edx

	missile_on_screen:					# Case 3: Missile is moving on screen (and isn't exploding)
		cmpl	oldpos_x, %esi			# has x changed?
		jne		mp1_missile_redraw		# if yes, redraw.

		cmpl	oldpos_y, %edi			# has y changed?
		je		next					# if neither x nor y has changed, just move on.

	mp1_missile_redraw:					# 1. Erase at old position, 2. Redraw at new position									
		pushl	%edx					# Save edx
		pushl	%eax					# Push eax to stack
		movb	$32, %cl				# Set cl to " " to erase missile at current position.
		movl	screen_width, %eax		# eax = 80
		movl	oldpos_y, %ebx
		shr		$16, %ebx				# find game coordinates of oldpos_y
		mull	%ebx					# edx:eax = screen_width * old_y
		movl	oldpos_x, %ebx
		shr		$16, %ebx				# find game coordinates of oldpos_x
		addl	%ebx, %eax				# eax += old_x	<- eax = index
		addl	%eax, %eax						# 2 char per index
		call	mp1_poke
		popl	%eax					#restore eax, using 1 copy of eax on stack

										# Redraw
		movb	C(%eax), %cl			# move missile character to %cl to redraw missile
	redraw_exploding:	
		pushl	%eax					# save eax
		movl	screen_width, %eax		# eax = 80
		mull	%edi					# set correct index for pixel edx:eax = eax * edi = 80 * y: (pixel[index] <- index = screen_width * y coordinate)
		addl	%esi, %eax				# ^(index = screen_width * y + x)
		addl	%eax, %eax						# 2 char per index
		call	mp1_poke				# print to screen (eax = index, cl = char)
		popl	%eax					# restore eax after drawing missile
		popl	%edx					# restore edx after drawing missile (pushed @ line 221)

	next:
		movl	%eax, %edx				# update previous node (prev = curr)
		movl	NEXT(%eax), %ebx		# move to next missile in the list (curr = curr->next)
		movl	%ebx, %eax				# ^
		jmp 	start					# update the next missile!

	update_done:
		movl 	save_eax, %eax 			# restore registers
		movl 	save_ebx, %ebx
		movl 	save_ecx, %ecx
		movl 	save_edx, %edx
		movl 	save_esi, %esi
		movl 	save_edi, %edi
		
		leave
		ret								# return - function complete.
#----------------------------------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------------------------------
mp1_missile_remove:					# 1. Erase missile from old (x,y) on screen, 
									# 2. Remove missile from linked list, 
									# 3. Deallocate missile memory
									# Note: This function saves both callee and caller-saved registers for convenience
		pushl	%ebp					# Modify stack pointer, save ebp
		movl 	%esp, %ebp		
		pushl	%ebx					# save callee-saved registers
		pushl	%esi
		pushl	%edi

		pushl	%edx					# save edx before mp1_poke
		pushl	%eax					# save eax before mp1_poke
		movb	$32, %cl				# ERASE Set cl to " ". 
		movl	screen_width, %eax		# eax = 80
		mull	oldpos_y				# edx:eax = screen_width * old_y (mul M[oldpos_y])
		addl	oldpos_x, %eax			# eax += old_x	<- eax = index
		addl	%eax, %eax
		call	mp1_poke
		popl	%eax					# restore eax and edx
		popl	%edx					
										# REMOVE missile from linked list
		cmpl	$0, %edx				# If previous (edx) is NULL, then that means we are removing the first node. (prev == NULL)
		je		update_head				# To remove the first node, we'll need to update head.
		movl	NEXT(%eax), %ebx		# If (prev != NULL), Set prev->next = curr->next
		movl	%ebx, NEXT(%edx)		# ^. Now, go free the missile.

	free_missile:						# FREE		
		pushl	%edx					# prepare to call: save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax					# push args - eax
		call 	mp1_free				# free current missile
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
									# Save registers
		pushl	%edx				# save caller-saved regs 								
		pushl	%ecx					
		pushl 	%eax	

		pushl	%ebx				# save callee-saved registerss
		pushl	%esi
		pushl	%edi

		movl	$0, %edi			# Set base counter to 0 (we're drawing the first base, or base[0])
		movl	base_alive, %edx	# put base_alive into %edx so we can look at the bits

	next_city:
		movl	$0, %esi			# Set counter esi to 0 (for first character)
		shr		$8, %edx			# get rid of the padding/previous city CCCX -> CCC
		movl	city_start, %eax	# Initialize Registers
		addl	%edi, %eax			# Add base offset to pixel index
		addl	%esi, %eax			# Add character offset to pixel index
		addl	%eax, %eax			# 2 characters per pixel
		addl	$20, %edi			# Add 20 pixels (40 bytes) to base_offset in preparation to draw the next base
		cmpl	$60, %edi			# If offset is 120, we're done because it means we've drawn 3 cities already.
		je		cities_done		
	
	next_character:
		cmpb	$0, %dl				# Check if base is alive/dead by looking at lowest byte of edx
		jnz		live_city			# Draw a live city if base_alive != 0 for the current city						
	dead_city:						# Dead city
		leal	dead_base_pic, %ebx	# Load address of dead_base into ebx
		movb	(%ebx, %esi), %cl  	# Load string[esi] into cl
		jmp		draw_character		# with eax = index and cl = char, output to screen.
		
	live_city:	
		leal	base_pic, %ebx 		# Load address of base_pic into ebx
		movb	(%ebx, %esi), %cl  	# Load string[esi] into cl. We're ready to ouput now.

	draw_character:
		pushl	%eax				# Save registers before function call
		pushl	%edx
		call	mp1_poke			# Draw to screen
		pop		%edx				# Restore regs
		pop		%eax
		addl	$1, %esi			# increment counter esi
		cmpl	$5, %esi			# string[5] is after the last element, so move to next city 		
		je		next_city			
		jmp 	next_character		# if we're not done drawing the city, move to next char.

	cities_done:					# Restore registers
		popl	%edi				# Restore callee-saved registers
		popl	%esi	
		popl	%ebx

		popl	%eax				# restore caller-saved regs
		popl	%ecx					
		popl	%edx				
		
		leave
		ret
#----------------------------------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------------------------------
redraw_crosshair:					#part 3 of mp1_rtc_tasklet

	# Register Use:
	# eax - pixel index (will also hold crosshair X during compute process)
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

		movl	crosshairs_x, %eax	# Load crosshair coordinates
		movl	crosshairs_y, %ebx	# 
									# Compute correct pixel
		movl	$80, %edx			# Load screen width (80) into esi
		mull	%edx				# eax = eax * 80 (index = x*screen_width)
		addl	%ebx, %eax
		movb	$43, %cl			# Load crosshair character (43) to cl. eax = index, cl = "+"
		addl	%eax, %eax					# 2 char per index
		call	mp1_poke			# Output to screen
									# Restore Registers			
		popl	%edi				# Restore callee-saved registers
		popl	%esi	
		popl	%ebx
		
		leave
		ret
#----------------------------------------------------------------------------------------------------------------------------
