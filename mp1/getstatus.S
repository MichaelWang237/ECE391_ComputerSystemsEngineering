movl	mp1_score, %ecx		# put score into ecx
		movl	$0, %ebx			
		movl	base_alive, %eax	# eax = CCCX
		
		movl	$3,	%edx			# number of cities left to check
	city_status:
		shr 	$8, %eax			# get rid of padding					
		cmpb	$0, %al				# check lowest 8 bits
		jne		status_alive		#
		
		shl		$1,	%ebx			# If city is dead, just shift

	status_alive:
		addl	$1, %ebx
		shl		$1, %ebx

	next_city_status:
		decl	%edx
		cmpl	$0, %edx			# 
		jg		city_status
		shl		$16, %ebx			# shift left 16 times to clear low bits for score and shift city status into correct pos.
		addw	%cx, %bx			# put score in lower 16 bits of ebx
		
		pushl	%edx				# save caller-saved regs/push arg								
		pushl	%ecx	
		pushl	%eax
		pushl	$32
		call 	mp1_malloc			# allocate memory. eax holds the pointer now
		pushl	$32					# push n = 32
		pushl	%eax				# push from = eax
		pushl	%esi				# push to = esi
		call	mp1_copy_to_user	# copy score into low 16 bits from mp1_score (copy_to_user)
		cmpl	$0, %eax			
		jne		get_status_invalid	# copy failed. Return -1
		pop		%esi				#pop args from copy_to_user, 
		pop		%eax				#eax = ptr
		call	mp1_free			#deallocate memory to avoid a memory leak
		pop		%eax
		pop		%eax		

		popl	%eax				# Restore caller-saved registers
		popl	%ecx
		popl	%edx
		movl	$0, %eax			# return 0.
		jmp		get_status_done

	get_status_invalid:
		pop		%esi				#pop args from mp1_malloc and copy_to_user
		pop		%eax
		call	mp1_free			#deallocate memory to avoid a memory leak
		pop		%eax
		pop		%eax		

		popl	%eax				# Restore caller-saved registers
		popl	%ecx
		popl	%edx
		movl	$-1, %eax			# return -1.