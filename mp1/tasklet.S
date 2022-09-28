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

