pushl	%edx				# save caller-saved regs								
		pushl	%ecx	
		pushl	%eax
		movl	$36, %ebx			# size of missile = (4 + 2*4 + 2*4 + 2*4 + 4 + 1) + 3(for alignment) = 36 bytes
		
		pushl 	%ebx				# push ebx as argument to malloc
		call 	mp1_malloc			# allocate memory. eax holds the pointer now
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

		movl	mp1_missile_list, %ebx 			# set missile's next to 1st missile on list
		movl	%ebx, NEXT(%eax)		
		movl	%eax, mp1_missile_list			# new missile becomes head

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