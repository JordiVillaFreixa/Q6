! Q6: A comprehensive simulation package for molecular dynamics simulations and 
! free energy calculations, including empirical valence bond simulations, 
! linear interaction energy calculations, and free energy perturbation.
! 
! Copyright © 2017 Johan Åqvist, John Marelius, Shina Caroline Lynn Kamerlin and Paul Bauer
! 
! This program is free software; you can redistribute it and/or modify it under the 
! terms of the GNU General Public License as published by the Free 
! Software Foundation; either version 2 of the License, or any later version.
! 
! This program is distributed in the hope that it will be useful, 
! but WITHOUT ANY WARRANTY; without even the implied warranty of 
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
! See the GNU General Public License for more details.
! 
! You should have received a copy of the GNU General Public License along with 
! this program; if not, write to the Free Software Foundation, Inc., 51 Franklin 
! Street, Fifth Floor, Boston, MA  02110-1301, USA. Also add information on 
! how to contact you by electronic and paper mail.
! qatom.f90
! by John Marelius, Johan Åqvist & Martin Almlöf
! Q-atom force field data and FEP file reading

module QATOM
use SIZES
use NRGY
use MISC
use PRMFILE
use INDEXER
use GLOBALS
!use MPIGLOB
use TOPO

implicit none

!constants
	character(*), private, parameter	:: MODULE_NAME    = 'Q-atom'
	character(*), private, parameter	:: MODULE_VERSION = '5.06'
	character(*), private, parameter	:: MODULE_DATE    = '2014-01-01'

!-----------------------------------------------------------------------
!	fep/evb information
!-----------------------------------------------------------------------

	integer, parameter			::	max_states		= 10
! no longer parameter, final value assigned later
	integer         			::	max_qat			= 100
	integer, parameter			::	max_link		= 10

	integer						::	nstates, nqat

	!******PWadded this variable
	!Topology atom number of the switching atom of the Q-atoms
	!Needed if periodic boundaries are used
	integer						::  qswitch

	integer 	::	offset !offset number for topology atom numbers
	logical						::	qvdw_flag
	logical						::	qq_use_library_charges
	integer(AI), allocatable	::	iqseq(:)
	integer, allocatable			::	qiac(:,:)
	character(len=KEYLENGTH), allocatable	::qtac(:)
	integer																::	nqexpnb
	integer(AI), allocatable							::	iqexpnb(:), jqexpnb(:)

	integer									::	nqlib
	real(kind=prec), allocatable		::	qcrg(:,:)
	real(kind=prec), allocatable		::	qmass(:)
	real(kind=prec), allocatable		::	qavdw(:,:), qbvdw(:,:)

	integer				::	nqbond

	type QBOND_TYPE
		integer(AI)		::	i,j
		integer(AI)		::	cod(max_states)
	end type QBOND_TYPE

	type QBONDLIB_TYPE
		!Morse diss. en, Morse Alpha, Morse/Harm. r0
		real(kind=prec)					::	Dmz, amz, r0
		!Harm. force const
		real(kind=prec)					::	fk
	end type QBONDLIB_TYPE

	type(QBOND_TYPE), allocatable	 :: qbnd(:)
	type(QBONDLIB_TYPE), allocatable :: qbondlib(:)


	type QANGLE_TYPE
		integer(AI)				::	i,j,k
		integer(AI)			::	cod(max_states)
	end type QANGLE_TYPE

	integer						::	nqangle

	type(QANGLE_TYPE), allocatable::	qang(:)
	type(ANGLIB_TYPE), allocatable::	qanglib(:)

	integer												::	nqtor
!make sure we have everything as types
!Paul October 2014
	type QTORSION_TYPE
		integer(AI)			:: i,j,k,l
		integer(AI)			:: cod(max_states)
	end type QTORSION_TYPE

	type QTORLIB_TYPE
		real(kind=prec)				:: fk,rmult,deltor,paths
	end type QTORLIB_TYPE

	type QIMPLIB_TYPE
		real(kind=prec)				:: fk,imp0
	end type QIMPLIB_TYPE

	type(QTORSION_TYPE),allocatable		:: qtor(:),qimp(:)
	type(QTORLIB_TYPE),allocatable		:: qtorlib(:)
	type(QIMPLIB_TYPE),allocatable		:: qimplib(:)

	integer						::	nqimp

	integer						::	nang_coupl,ntor_coupl,nimp_coupl
	integer(AI),allocatable					::	iang_coupl(:,:)!3,max_qat)
	integer(AI),allocatable					::	itor_coupl(:,:)!3,max_qat)
	integer(AI),allocatable					::	iimp_coupl(:,:)!3,max_qat)

	integer						::	nqshake
	integer(AI),allocatable 			::	iqshake(:),jqshake(:)
	real(kind=prec),allocatable			::	qshake_dist(:,:)!max_qat,max_states)

	integer						::	noffd
	type(OFFDIAG_SAVE), allocatable::	offd(:)
	type(OFFDIAG_AUX), allocatable::	offd2(:)

    integer						::	nexspec
	type SPECEX_TYPE
		integer(AI)				::	i,j
		logical					::	flag(max_states)
	end type SPECEX_TYPE
	type(SPECEX_TYPE), allocatable :: exspec(:)

	! Monitoring of nonbonded interactions between selected groups of atoms
	type monitor_group_pair_TYPE
		integer					::	i,j
! where to start and stop reading the list containing the precomputed
! interactions for monitor groups
                integer                                         ::      lstart(max_states),lend(max_states) 
		real(kind=prec)					::	Vel(max_states), Vlj(max_states)
		real(kind=prec)					::	Vwel, Vwlj, Vwsum
	end type  monitor_group_pair_TYPE
	type(monitor_group_pair_TYPE), allocatable::monitor_group_pair(:)

	type monitor_atom_group_TYPE
	  integer, pointer			::	atom(:)	! the atoms
	  integer								::	n		! #atoms
	end type monitor_atom_group_TYPE

	type (monitor_atom_group_TYPE), allocatable::monitor_atom_group(:)

	!the maximal number of atoms in a group to be monitored
	!this is limited by the line length used in the prmfile module!

	integer, parameter			::	MAX_ATOMS_IN_SPECIAL_GROUP=30

	integer						::	monitor_group_pairs, monitor_groups

	!type holding all scaling factors for electostatic interactions in qq-pairs
	type qq_el_scale_TYPE
		integer(AI)      ::iqat,jqat
		real(kind=prec)          ::el_scale(max_states)! to hold the el_scale for different states "masoud Oct_2013"
	end type qq_el_scale_TYPE

	type(qq_el_scale_TYPE),allocatable             :: qq_el_scale(:)

	integer               ::nel_scale !number of defined scale factors

    	integer						::	tmpindex,numsoftlines,i2
    	real(kind=prec), allocatable				::	sc_lookup(:,:,:), alpha_max(:,:)
		real(kind=prec)						::	sc_aq,sc_bq,sc_aj,sc_bj,alpha_max_tmp
		logical						::  softcore_use_max_potential

!New data structure for keeping the bond information
!for FEP file sanity checks
!Paul Ocyober 2014
	type Q_SANITYCHECK
		integer		::	i,j
		integer(AI)	::	brk_state,set_state
	end type Q_SANITYCHECK
	type Q_SAN_CHECK
		integer(AI)		:: i,j,k,l
		integer(AI)		:: istate,jstate,abreak,cbreak
		integer(AI)		:: num,code
		integer(AI)		:: brk_state,set_state
	end type Q_SAN_CHECK
!Added memory management stuff
	integer			:: alloc_status_qat

!-----------------------------------------------------------------------
!	fep/evb energies
!-----------------------------------------------------------------------
	type(OQ_ENERGIES), allocatable::	EQ(:)
	type(OQ_ENERGIES), allocatable:: old_EQ(:)
        type(Q_ENERGIES), allocatable :: EQ_save(:)
	real(kind=prec)						::	Hij(max_states,max_states)
	real(kind=prec),allocatable				::	EMorseD(:)!max_qat)
        TYPE(qr_vec),allocatable				::	dMorse_i(:)!3,max_qat)
        TYPE(qr_vec),allocatable				::	dMorse_j(:)!3,max_qat)

!miscellany
	logical						::	use_new_fep_format

contains

!-------------------------------------------------------------------------

subroutine qatom_savetowrite(saveEQ,pos)
! adds one set of energies to final EQ_save array in correct position
! arguments
TYPE(OQ_ENERGIES)               :: saveEQ(:)
integer                         :: pos
! locals
integer                         :: istate

do istate = 1, nstates
EQ_save(istate)%lambda          = saveEQ(istate)%lambda
EQ_save(istate)%q(pos)%bond     = saveEQ(istate)%q%bond
EQ_save(istate)%q(pos)%angle    = saveEQ(istate)%q%angle
EQ_save(istate)%q(pos)%torsion  = saveEQ(istate)%q%torsion
EQ_save(istate)%q(pos)%improper = saveEQ(istate)%q%improper
EQ_save(istate)%qx(pos)         = saveEQ(istate)%qx
EQ_save(istate)%qq(pos)         = saveEQ(istate)%qq
EQ_save(istate)%qp(pos)         = saveEQ(istate)%qp
EQ_save(istate)%qw(pos)         = saveEQ(istate)%qw
EQ_save(istate)%total(pos)      = saveEQ(istate)%total
EQ_save(istate)%restraint(pos)  = saveEQ(istate)%restraint

end do
end subroutine qatom_savetowrite

subroutine qatom_startup
	! initialise used modules
	call prmfile_startup
	call nrgy_startup
end subroutine qatom_startup

!-------------------------------------------------------------------------

subroutine qatom_shutdown
	integer						::	alloc_status_qat,ii
	do ii=1,nstates
	if (allocated(EQ_save(ii)%qx))    deallocate(EQ_save(ii)%qx,stat=alloc_status_qat)
	if (allocated(EQ_save(ii)%qq))    deallocate(EQ_save(ii)%qq,stat=alloc_status_qat)
	if (allocated(EQ_save(ii)%qp))    deallocate(EQ_save(ii)%qp,stat=alloc_status_qat)
	if (allocated(EQ_save(ii)%qw))    deallocate(EQ_save(ii)%qw,stat=alloc_status_qat)
	if (allocated(EQ_save(ii)%total)) deallocate(EQ_save(ii)%total)
	end do
	deallocate(EQ,EQ_save, stat=alloc_status_qat)	

	if (allocated(old_EQ)) deallocate(old_EQ, stat=alloc_status_qat)
	deallocate(iqseq, qiac, iqexpnb, jqexpnb, qcrg, stat=alloc_status_qat)
	deallocate(qmass, stat=alloc_status_qat)
	deallocate(qavdw, qbvdw, stat=alloc_status_qat)
	deallocate(qbnd, qbondlib, stat=alloc_status_qat)
	deallocate(qang, stat=alloc_status_qat)
	deallocate(qanglib, stat=alloc_status_qat)
	deallocate(qtor, stat=alloc_status_qat)
	deallocate(qimp, stat=alloc_status_qat)
	deallocate(qtorlib, stat=alloc_status_qat)
	deallocate(qimplib, stat=alloc_status_qat)
	deallocate(exspec, stat=alloc_status_qat)
	deallocate(offd, offd2, stat=alloc_status_qat)
	if (allocated(qq_el_scale)) deallocate(qq_el_scale)
	if (allocated(monitor_atom_group)) deallocate(monitor_atom_group)
	if (allocated(monitor_group_pair)) deallocate(monitor_group_pair)
	if (allocated(qtac)) deallocate(qtac)
	if (allocated(alpha_max)) deallocate(alpha_max)
	if (allocated(sc_lookup)) deallocate(sc_lookup)
        if (allocated(iang_coupl)) deallocate(iang_coupl)
        if (allocated(itor_coupl)) deallocate(itor_coupl)
        if (allocated(iimp_coupl)) deallocate(iimp_coupl)
        if (allocated(iqshake)) deallocate(iqshake)
        if (allocated(jqshake)) deallocate(jqshake)
        if (allocated(qshake_dist)) deallocate(qshake_dist)
        if (allocated(EMorseD)) deallocate(EMorseD)
        if (allocated(dMorse_i)) deallocate(dMorse_i)
        if (allocated(dMorse_j)) deallocate(dMorse_j)
end subroutine qatom_shutdown

!-------------------------------------------------------------------------

logical function qatom_old_load_atoms(fep_file)
!arguments
	character(*), intent(in)	::	fep_file
  ! *** local variables
  integer					::	i
  !.......................................................................
	qatom_old_load_atoms = .false.

  call centered_heading('Reading Q atom list','-')
  ! --> fep file (4)

  open (unit=4,file=fep_file,status='old',form='formatted', &
       action='read')

  ! --- # states, # q-atoms

  read (4,*) nstates,nqat
  write (*,20) nstates,nqat
20 format ('No. of fep/evb states    = ',i5,5x, &
       'No. of fep/evb atoms     = ',i5)
  !allocate memory for qatom list
  allocate(iqseq(nqat))


  read (4,*) (iqseq(i),i=1,nqat)
  write (*,40) (iqseq(i),i=1,nqat)
40 format ('Atom nos.:',10i6)
	qatom_old_load_atoms = .true.
end function qatom_old_load_atoms

!-------------------------------------------------------------------------

logical function qatom_load_atoms(fep_file)
	!arguments
	character(*), intent(in)	::	fep_file
	! *** local variables
	integer					::	i,j,iat,ires,iatq
	integer					::	s, topno, icase, stat, last, add_res
	integer					::	type_count !counts number of parameters
	logical					::	yes
	character(len=4)		::	offset_name
	character(len=4)		::	res_name
	character(len=7)		::	res_str
	character(len=50)		::	line
	character(len=50)		::	word
	character(len=4), allocatable :: names(:)
	integer					::	offset_residue, max_res, resno
	integer, allocatable	::  residues(:)
        integer                 :: tmp_states
  !.......................................................................

	use_new_fep_format = .true.
	qatom_load_atoms = .true.				!assume this for a start
	softcore_use_max_potential = .false.	!default

	call centered_heading('Reading Q atom list','-')

	if(.not. prm_open_section('atoms', fep_file)) then !it's not a new file
		write(*,'(a)') &
			'>>> WARNING: No [atoms] section in fep file. Aborting file loading.'
		call prm_close
		use_new_fep_format = .false.
		qatom_load_atoms = .false.
!We stop supporting old FEP files to make the code easier to maintain
!Executive decision, Paul Bauer 07102014

		return
	end if

	if(.not. prm_open_section('FEP')) then
                tmp_states = 1
                if (tmp_states .ne. nstates) then
                        qatom_load_atoms = .false.
                        write(*,*) '>>>>> ERROR: Mismatch between nstates in input and FEP file'
                end if
		nstates = tmp_states
		write(*,21, advance='no') nstates
	else
		if(.not.prm_get_integer_by_key('states', tmp_states)) then
			tmp_states = 1
                        if(tmp_states.ne.nstates) then
                                qatom_load_atoms = .false.
                                write(*,*) '>>>>> ERROR: Mismatch between nstates in input and FEP file'
                        end if
			write(*,21) nstates
		else
                        if(tmp_states.ne.nstates) then
                                qatom_load_atoms = .false.
                                write(*,*) '>>>>> ERROR: Mismatch between nstates in input and FEP file'
                        end if
			write(*,20) nstates
		end if
		yes = prm_get_logical_by_key('qq_use_library_charges', qq_use_library_charges, .false.)
		yes = prm_get_logical_by_key('softcore_use_max_potential', softcore_use_max_potential, .false.)

		offset = -1
		!should an offset be applied to topology atom numbers?
		if(prm_get_integer_by_key('offset', offset)) then
			!got an atom number offset
			if(offset < 1 .or. offset > nat_solute) then
				!it's invalid
				write(*, '(a,i5)') '>>>>> ERROR: Invalid topology atom number offset value:', offset
				qatom_load_atoms = .false.
				return
			end if
			ligand_offset = offset
		elseif(prm_get_string_by_key('offset_name', offset_name)) then
			do i = 1, nres_solute
				if(offset_name == res(i)%name) then
					offset = res(i)%start - 1
					exit
				end if
			end do
			if(offset == -1) then !not found
				write(*, '(a,a4,a)') '>>>>> ERROR: Residue name ',offset_name, &
					'not found.'
				qatom_load_atoms = .false.
				return
			end if
			ligand_offset = offset
		elseif(prm_get_integer_by_key('offset_residue', offset_residue)) then
			if(offset_residue < 1 .or. offset_residue > nres_solute) then
				write(*, '(a,i5)') '>>>>> ERROR: Invalid residue number for offset:',offset_residue
				qatom_load_atoms = .false.
				return
			end if
			offset = res(offset_residue)%start - 1
		else
			offset = 0
		end if
	end if

	if(nstates == 0) then
		write(*,'(/,a)') &
			'>>>>> ERROR: Number of states must be at least 1. Aborting.'
		qatom_load_atoms = .false.
		return
	end if

	yes = prm_open_section('atoms') !by now we know it's there
	type_count = prm_count('atoms')	!count number of q-atom lines
	if(type_count == 0) then
		write(*,'(a)') &
			'>>> WARNING: Number of Q-atoms is zero. Fep file will not be loaded.'
		call prm_close
		!qatom_load_atoms = .false. !this condition IS OK.
		return
	end if

	if (.not. prm_get_line(line)) then
		write(*, '(a)') ">>>>> ERROR: reading line in 'atoms' section"
		qatom_load_atoms = .false.
		return
	end if
	icase=0
	read(line, fmt=*, iostat=stat) word, i !read integer from value
	if (stat == 0) then
		read(word, fmt=*, iostat=stat) i !read integer from value
		if (stat == 0) then
			icase = 1   !int_int
		else
			icase = 2 !string_int
		end if
	else
		icase = 3  !string_string
	end if

	select case(icase)
	case (1)
		nqat = prm_max_enum('atoms', type_count) !count number of q-atoms & get highest q-atom number
		!allocate memory for qatom list
		allocate(iqseq(nqat))
		yes = prm_open_section('atoms') !rewind section
		do i = 1, type_count
			if(prm_get_int_int(s, topno)) then
				if(topno + offset < 1 .or. topno + offset > nat_solute) then
					write(*, '(a,i5,a, i2)') '>>>>> ERROR: invalid topology atom number', &
						topno + offset, ' for Q-atom',i
					qatom_load_atoms = .false.
				end if
				iqseq(s) = topno + offset
			else
				write(*,'(a,i2)') &
					'>>> WARNING: Failed to read Q-atom ',i
				qatom_load_atoms = .false.
			end if
		end do
	!Input is of type 'res xx'
	case(2)
		yes = prm_open_section('atoms') !rewind section
		if (offset > 0) then
			write(*,'(a)') &
				'>>> WARNING: Offset can only be used when defining q-atoms with atom nubers. \n Offset will be set to zero.'
				offset=0
		end if

		max_res = prm_max_enum2('atoms', type_count) !count number of residues & get highest residue number
		if (max_res > nres_solute) then
			write(*, '(a,i5)') '>>>>> ERROR: invalid topology solute residue number', max_res
			qatom_load_atoms = .false.
			return
		end if
		allocate(residues(type_count))
		nqat=0
		!Count number of q-atoms
		do i = 1, type_count
			if(prm_get_string_int(res_str, resno)) then
				call upcase(res_str)
				if(res_str == 'RES' .or. res_str == 'RESIDUE') then
					residues(i)=resno
					if (resno < nres_solute) then
						nqat = nqat + (res(resno+1)%start - res(resno)%start)
					else
						nqat = nqat + ((nat_solute +1) - res(resno)%start)
					end if
				else
					write(*, '(a)') ">>>>> ERROR: invalid selection syntax in fep file, section 'atoms'"
					qatom_load_atoms = .false.
					return
				end if
			else
				write(*,'(a,i2)') &
					'>>> WARNING: Failed to read Q-residue ',i
				qatom_load_atoms = .false.
			end if
		end do
		allocate(iqseq(nqat))
		iatq=1
		!Now assign iqseq with proper topology atom numbers
		do i = 1, type_count
			ires=residues(i)
			if (ires < nres_solute) then
				last=res(ires+1)%start-1
				do iat = res(ires)%start,last
					iqseq(iatq)= iat
					iatq=iatq+1
				end do
			else
				do iat = res(ires)%start, nat_solute
					iqseq(iatq)= iat
					iatq=iatq+1
				end do
			end if
		end do
		offset = 0; !offset, offset not compatible with this definition
		write (*,31) (residues(i),i=1,type_count)

	!it is string_string, 'all TYPE'
    case(3)
		yes = prm_open_section('atoms') !rewind
		if (offset > 0) then
			write(*,'(a)') &
				'>>> WARNING: Offset can only be used when defining q-atoms with atom nubers. \n Offset will be set to zero.'
				offset=0
		end if

		allocate(names(type_count))
		do i=1, type_count
			if(.not. prm_get_string_string(res_str, res_name)) then
				write(*, '(a)') ">>>>> ERROR: invalid syntax in fep file, section 'atoms'"
				qatom_load_atoms = .false.
				return
			end if
			call upcase(res_str)
			if(.not. (res_str == 'ALL')) then
				write(*, '(a)', advance='no') ">>>>> ERROR: invalid syntax in fep file, &
					&section 'atoms': ",res_str
				qatom_load_atoms = .false.
				return
			end if
			call upcase(res_name)
			names(i)=res_name
		end do
		add_res=0
		allocate(residues(nres_solute))  !allocate for worst case
		do ires=1,nres_solute
			do j=1,type_count
				if(names(j) == res(ires)%name) then
					add_res=add_res+1
					residues(add_res)=ires
					exit
				end if
			end do
		end do
		if (add_res == 0) then
			write(*, '(a)') ">>>>> ERROR: No matching residues found in topology. Could not assign qatoms."
			qatom_load_atoms = .false.
			return
		end if
		!Count number of q-atoms
		do i = 1, add_res
			ires=residues(i)
			if (ires < nres_solute) then
				nqat = nqat + (res(ires+1)%start - res(ires)%start)
			else
				nqat = nqat + (nat_solute +1 - res(ires)%start)
			end if
		end do
		allocate(iqseq(nqat))
		iatq=1
		!Now assign iqseq with proper topology atom numbers
		do i = 1, add_res
			ires=residues(i)
			if (ires < nres_solute) then
				last=res(ires+1)%start-1
				do iat = res(ires)%start,last
					iqseq(iatq)= iat
					iatq=iatq+1
				end do
			else
				do iat = res(ires)%start, nat_solute
					iqseq(iatq)= iat
					iatq=iatq+1
				end do
			end if
		end do
		offset = 0; !offset, offset not compatible with this definition
		write (*,31) (residues(i),i=1,add_res)

	case default
		write(*,'(a,i2)') &
			">>> ERROR: Failed to read fep file. Syntax error in 'atoms' section."
		qatom_load_atoms = .false.
		return
	end select

  if (allocated(residues)) deallocate(residues)
  if (allocated(names)) deallocate(names)

  write (*,30) nqat
  write (*,40) (iqseq(i),i=1,nqat)

20 format ('No. of fep/evb states    = ',i5)
21 format ('Default fep/evb states   = ',i5)
30 format ('No. of fep/evb atoms     = ',i5)
31 format ('Assigning q-atoms from residues: ',5i6)
40 format ('Atom nos.:',10i6)

end function qatom_load_atoms


!-------------------------------------------------------------------------

!logical function qatom_old_load_fep()
!Removed, we stop supporting deprecated FEP file formats
!Executive decision, Paul Bauer 07102014
!end function qatom_old_load_fep

!-----------------------------------------------------------------------
logical function qatom_load_fep(fep_file)
!arguments
	character(*), intent(in)	::	fep_file
  ! *** local variables
  character(len=200)		::	line
  integer(AI)                           :: i,j,k,l,iat,ii
  integer(AI)                           :: nqcrg=0,nqbcod=0,nqacod=0,nqtcod=0,nqicod=0
  character(len=40)                     :: section
  logical, allocatable, dimension(:)    :: type_read
  integer                               :: type_count, filestat
  real(kind=prec)                       :: el_scale(max_states) !local variable for scaling of different states "masoud Oct_2013"
  integer                   ::  stat
!New temporary variables for sanity checks
!Paul October 2014, ICM meeting used for something useful
  integer(AI)                         :: test_state,broken_state
  logical,allocatable                   :: testarray(:)
  type(Q_SANITYCHECK),allocatable       :: break_bonds(:)
  type(Q_SAN_CHECK),allocatable         :: break_angles(:)
  type(Q_SAN_CHECK),allocatable         :: break_torsions(:)
  type(Q_SAN_CHECK),allocatable         :: break_impropers(:)
  integer                               :: nbreak_ang=-1
  integer                               :: nbreak_tor=-1
  integer                               :: nbreak_imp=-1
  logical                               :: have_break = .false.,angle_set = .false.,torsion_set = .false.
  logical                               :: improper_set = .false.
  integer                               :: ibreak,jbreak,kbreak,lbreak,istate,jstate,cbreak,abreak
  integer                               :: nbreak_bnd = 0
  type(ANGLIB_TYPE),allocatable         :: tmp_qanglib(:)
  type(QANGLE_TYPE),allocatable         :: tmp_qang(:)
  type(QTORLIB_TYPE),allocatable        :: tmp_qtorlib(:)
  type(QTORSION_TYPE),allocatable       :: tmp_qtor(:)
  type(QIMPLIB_TYPE),allocatable        :: tmp_qimplib(:)
  type(QTORSION_TYPE),allocatable       :: tmp_qimp(:)
!for setting vdW arrays to default
  logical					:: vdw_from_topo = .false.
  integer                                       :: tmp_qcp_num
	!temp. array to read integer flags before switching to logicals
	integer					::	exspectemp(max_states)
	character(len=keylength)	:: qtac_tmp(max_states)

	!temp array for reading special atom group members
	integer                   ::  temp_atom(MAX_ATOMS_IN_SPECIAL_GROUP)


	if(.not. use_new_fep_format) then
!We stop supporting deprecated file formats
!Executive decision, Paul Bauer 07102014
		write(*,*) '>>>> ERROR: Old file format not supported'
		qatom_load_fep = .false.
		return
	end if

	qatom_load_fep = .true.

	if(.not. prm_open(fep_file)) then
		write(*,'(a,a)') '>>>>> ERROR: Could not open fep file ',trim(fep_file)
		qatom_load_fep = .false.
		return
	end if

	call centered_heading('Reading fep/evb strategy','-')

	!When PBC is used, a switching atom for the Q-atoms has to be defined.
	if( use_PBC ) then
		if( .not. prm_open_section('PBC') ) then
			write(*,51)
			qatom_load_fep = .false.
			return
		else
			if( .not. prm_get_integer_by_key('switching_atom', qswitch) ) then
				write(*,50)
				qatom_load_fep = .false.
			else
				qswitch = qswitch + offset
				write (*,'(a,i6,a)') 'Using topology atom number ',qswitch,' when creating q-atom based nonbond lists.'
			end if
		end if
	end if
51		format('>>>>> ERROR: Section PBC is required when using periodic boundary.')
50		format('>>>>> ERROR: Switching atom could not be read.')



  !allocate memory for qatom arrays
	allocate(qiac(nqat,nstates))
	allocate(testarray(nstates))
	!qcrg may be allocated in MD to copy topology charges
	if(.not. allocated(qcrg)) allocate(qcrg(nqat,nstates))

	!read flag for use of library charges in qq-nonbond
	!assume section FEP is open
	! --- Set new charges
	section = 'change_charges'
	nqcrg = prm_count(section)
	if(nqcrg > 0) then
		write (*,60) nqcrg
		if(qq_use_library_charges) then
			write(*,'(a)') 'Intra-Q-atom electrostatic interactions will not be changed.'
		end if

60		format (/,'No. of changing charges  = ',i5)
		do i=1,nqcrg
			if(.not. prm_get_line(line)) goto 1000
			!read atom to check
			read(line,*,err=1000) iat
			if(iat < 1 .or. iat > nqat) then
				write(*,82) iat
				qatom_load_fep = .false.
				cycle !dont even try to read charges
			else if(iqseq(iat) == 0) then
				write(*,82) iat
				qatom_load_fep = .false.
				cycle !dont even try to read charges
			end if
			!read atom and all charges

			read (line,*, err=1000) iat,qcrg(iat,:)
		end do

		!list Q-atom charges
		write(*,29)
		write(*,30) ('state',i,i=1,nstates)
		do i=1,nqat
			write(*,31) i, qcrg(i,:)
		end do
		write(*,32) sum(qcrg(:,:), dim=1)

	end if
29	format('Effective Q-atom charges for all Q-atoms')
30	format('Q atom    charge in',7(1x,a5,i2))
31	format(     i6,t20,10f8.3)
32	format(/,'   SUM',t20,10f8.3)

82	format('>>>>> ERROR: ',i2,' is not a valid q-atom number')

	! Read Qatom type library only if iqvdw_flag is true
	section = 'atom_types'
	nqlib = prm_count(section)
	if(nqlib > 0) then
		write (*,120) nqlib
		if(ivdw_rule==VDW_GEOMETRIC) then
			write(*,130)
		else
			write(*,131)
		end if
		allocate(qtac(nqlib))
		call index_create(nqlib) !set up atom type name lookup table
		!clear read flag for all parameters
120		format (/,'No. of Q-atom types  = ',i5)
130		format('Name            Ai      Bi      Ci     ai Ai(1-4) Bi(1-4)    Mass')
131		format('Name            R*i     ei      Ci     ai R*i(1-4)ei(1-4)    Mass')

		allocate(qmass(nqlib), qavdw(nqlib,nljtyp), qbvdw(nqlib,nljtyp))

		do i=1,nqlib
			if(.not. prm_get_line(line)) goto 1000
			read (line,*, err=1000) qtac(i),(qavdw(i,k),qbvdw(i,k),k=1,nljtyp),qmass(i)
			write (*,140) qtac(i),(qavdw(i,k),qbvdw(i,k),k=1,nljtyp),qmass(i)
			if(.not. index_add(qtac(i), i)) then
				write(*,83) qtac(i)
				qatom_load_fep = .false.
			end if
		end do
140		format (a8,1x,f9.2,2f8.2,f6.2,f9.2,2f8.2)
83		format ('>>>>> ERROR: Could not enumerate q-atom type ',a,' Duplicate name?')
	else
!No types declared, build list with std types from topology
!Means every atom gets its own type -> waste of space
!Do this in the dark, set flag so that next section knows it!
		vdw_from_topo = .true.
		allocate(qtac(nqat))
		call index_create(nqat)
		allocate(qmass(nqat),qavdw(nqat,nljtyp), qbvdw(nqat,nljtyp))
		do i=1,nqat
			qtac(i) = tac(iac(iqseq(i)))
			qmass(i)= iaclib(iac(iqseq(i)))%mass
				qavdw(i,1:nljtyp)=iaclib(iac(iqseq(i)))%avdw(1:nljtyp)
				qbvdw(i,1:nljtyp)=iaclib(iac(iqseq(i)))%bvdw(1:nljtyp)
		end do
	end if

	! --- Set new vdw params
	section = 'change_atoms'
	iat = prm_max_enum(section, type_count)
	if(iat == 0) then
		qvdw_flag = .false.
!No vdW types defined, set values from topology
		if (vdw_from_topo) then
		do i=1,nqat
			do j=1,nstates
				qiac(i,j) = i
			end do
		end do
		end if
	else if(iat /= nqat .or. type_count /= nqat) then
		write(*,'(a)') '>>>>> ERROR: Atom types of Q-atoms must be given for every Q-atom!'
		qatom_load_fep = .false.
		return
	else
		qvdw_flag = .true.
		write (*,100)
100		format (/,'Assigning Q-atom types to all Q atoms:')
80		format('Q atom    atom type in',6(2x,a5,i2))
		write (*,80) ('state',i,i=1,nstates)
		do i=1,nqat !we know nqat = number of type_count
			!reading should not fail at this stage - get_line was called by prm_count!
			if(.not. prm_get_line(line)) goto 1000
        	read (line,*, err=1000) iat,qtac_tmp(1:nstates)
			write (*,'(i6,t25,6(a8,1x))') iat,qtac_tmp(1:nstates)
			do j = 1, nstates
				!check that atom type is defined and assign qiac(iat,j)
				if(.not. index_get(qtac_tmp(j), qiac(iat,j))) then
					write(*,113) qtac_tmp(j)
					qatom_load_fep = .false.
				end if
			end do !checking
		end do
	end if !if redefine atom types
112	format('>>>>> ERROR: ',a,' type ',i2,' has not been defined.')
113	format('>>>>> ERROR: Q-atom type ',a,' has not been defined.')

! --- Soft repulsion pairs
	section = 'soft_pairs'
	nqexpnb = prm_count(section)
	if(nqexpnb > 0) then
		write (*,144) nqexpnb
		write(*,145)
		allocate(iqexpnb(nqexpnb))
		allocate(jqexpnb(nqexpnb))
		do i=1,nqexpnb
			if(.not. prm_get_line(line)) goto 1000
			read(line,*, err=1000) j, k
			if(j < 1 .or. j > nqat .or. k < 1 .or. k > nqat) then
				write(*,148) j,k
				qatom_load_fep = .false.
				cycle !dont even try to read charges
			else if(iqseq(j) == 0 .or. iqseq(k) == 0) then
				write(*,148) j,k
				qatom_load_fep = .false.
				cycle !dont even try to read
			end if
			iqexpnb(i) = j
			jqexpnb(i) = k
			write (*,146) iqexpnb(i),jqexpnb(i)
		end do
	end if
144	format (/,'No. of soft repulsion non-bonded pairs = ',i5)
145	format('q-atom_i q-atom_j')
146	format (i8,1x,i8)
148	format('>>>>> ERROR: Invalid q-atom number in this group: ',4i5)

! --- Read scaling factors for el. interactions between qq-atoms
	section = 'el_scale'
	nel_scale = prm_count(section)
	if(nel_scale > 0) then
	allocate(qq_el_scale(nel_scale))
		write (*,154) nel_scale
		write(*,155) ('state',i, i=1,nstates) !heading for qq_el_scale at different states "masoud Oct_2013"
		do i=1,nel_scale
			if(.not. prm_get_line(line)) goto 1000
			read(line,*, err=1000) j, k, el_scale(1:nstates)
			if(j < 1 .or. j > nqat .or. k < 1 .or. k > nqat) then !Check if qatoms...
				write(*,148) j,k
				qatom_load_fep = .false.
				cycle
			else if(iqseq(j) == 0 .or. iqseq(k) == 0) then
				write(*,148) j,k
				qatom_load_fep = .false.
				cycle
			end if
            qq_el_scale(i)%iqat=j
            qq_el_scale(i)%jqat=k
            qq_el_scale(i)%el_scale(1:nstates)=el_scale(1:nstates) !assigning scale factor to qq_el_scale variable "masoud Oct_2013"
			write (*,156) qq_el_scale(i)%iqat,qq_el_scale(i)%jqat,qq_el_scale(i)%el_scale(1:nstates)
		end do
	end if
154	format (/,'No. of el. scaling factors between q-q-atoms = ',i5)
155	format('q-atom_i q-atom_j el_scale' , 7(1x,a5,i2))
156	format (i8,1x,i8,1x,7f8.2) !print out up to 7 states "masoud Oct_2013"

! --- Read special exclusions among quantum atoms
	section='excluded_pairs'
	nexspec = prm_count(section)
    if(nexspec > 0) then
		write (*,585) nexspec
		write(*,586) ('state',i, i=1,nstates)
		allocate(exspec(nexspec))

585		format (/,'No. of excluded non-bonded pairs = ',i5)
		do i=1,nexspec
			if(.not. prm_get_line(line)) goto 1000
			read(line,*, err=1000) exspec(i)%i, exspec(i)%j, exspectemp(1:nstates)
			exspec(i)%i = exspec(i)%i + offset
			exspec(i)%j = exspec(i)%j + offset
			write (*,587) exspec(i)%i,exspec(i)%j,exspectemp(1:nstates)
			do j = 1, nstates
				if(exspectemp(j) == 0) then
					exspec(i)%flag(j) = .false.
				elseif(exspectemp(j) == 1) then
					exspec(i)%flag(j) = .true.
				else
					write(*,592)
					qatom_load_fep = .false.
				end if
			end do
		end do
586	format('atom_i atom_j    excluded in', 7(1x,a5,i2))
587	format(i6,1x,i6,t29,7i8)
592		format('>>>>> ERROR: Special exclusion state flags are invalid.')
	end if


	! --- Set new bonds
	section='bond_types'
	nqbcod = prm_max_enum(section, type_count)
	if(nqbcod > 0 ) then
		allocate(type_read(nqbcod))
	type_read(:) = .false.
		allocate(qbondlib(nqbcod))
		write (*,150)
		write (*,'(a)') 'type #  Morse E_diss    alpha       b0  Harmonic force_k '

		do i=1,type_count
			if(.not. prm_get_line(line)) goto 1000
			read(line, *, iostat=filestat) j, qbondlib(j)%Dmz,qbondlib(j)%amz, &
				qbondlib(j)%r0
			if(filestat /= 0) then !could not read Morse - try harmonic
				read(line, *, iostat=filestat) j,qbondlib(j)%fk,qbondlib(j)%r0
				if(filestat /= 0) then
					goto 1000
				else
					!Harmonic OK - clear Morse
					qbondlib(j)%Dmz = zero
					qbondlib(j)%amz = zero
					type_read(j) =.true.
					write (*,226) j, qbondlib(j)%r0, qbondlib(j)%fk
				end if
			else
				!Morse OK - clear harmonic
				qbondlib(j)%fk = zero
				type_read(j) =.true.
				write (*,225) j,qbondlib(j)%Dmz,qbondlib(j)%amz, qbondlib(j)%r0
			end if
		end do
150		format (/,'Q-bond types:')
225		format(i6,6x,f8.2,1x,f8.2,1x,f8.2)
226		format(i6,24x,f8.2,10x,f8.2)
		write (*,*)
	end if

	section = 'change_bonds'
	nqbond = prm_count(section)
	if(nqbond > 0)  then
            ! allocate all stuff that was hard coded before
            allocate(iang_coupl(3,nqbond),itor_coupl(3,nqbond),iimp_coupl(3,nqbond),iqshake(nqbond) , &
                    jqshake(nqbond),qshake_dist(nqbond,max_states),EMorseD(nqbond) , &
                    dMorse_i(nqbond),dMorse_j(nqbond))
                    iang_coupl  = 0
                    itor_coupl  = 0
                    iimp_coupl  = 0
                    iqshake     = 0
                    jqshake     = 0
                    qshake_dist = zero
                    EMorseD     = zero
                    dMorse_i    = zero
                    dMorse_j    = zero
		write (*,160) nqbond
		write(*,161) ('state',i,i=1,nstates)
		allocate(qbnd(nqbond),stat=alloc_status_qat)
		allocate(break_bonds(nqbond),stat=alloc_status_qat)
		call check_alloc_general(alloc_status_qat,'Q bond arrays')
		break_bonds(:)%i=-1
		break_bonds(:)%j=-1
		break_bonds(:)%set_state=-1
		break_bonds(:)%brk_state=-1
		do i=1,nqbond
			if(.not. prm_get_line(line)) goto 1000
			read(line,*, err=1000) qbnd(i)%i, qbnd(i)%j, qbnd(i)%cod(1:nstates)
			qbnd(i)%i = qbnd(i)%i + offset
			qbnd(i)%j = qbnd(i)%j + offset
			write (*,162) qbnd(i)%i,qbnd(i)%j,qbnd(i)%cod(1:nstates)
			!check types
			testarray(:)=.false.
			do j=1,nstates
				if(qbnd(i)%cod(j) >0) then
					if (allocated(type_read)) then
					if(.not. type_read(qbnd(i)%cod(j))) then
						write(*,112) 'Q-bond', qbnd(i)%cod(j)
						qatom_load_fep = .false.
					end if
					else
					    write(*,112) 'Q-bond', qbnd(i)%cod(j)
					    qatom_load_fep = .false.
					end if
!Bond is tested for being present, to check if forming/breaking bonds
!are set as morse and not harmonic
					testarray(j)=.true.
				else
!Bond is not set
					testarray(j)=.false.
				end if
			end do
			have_break = .false.
			do j=1, nstates-1
!Trigger if bonds break or are always broken
				if ((testarray(j) .neqv. testarray(j+1)) .or. &
					(testarray(j).eqv.testarray(j+1).eqv. .false.)) then
!Now see if we have a forming or breaking bond set as morse
!make sure we only test for the bond that is actually there
				if(testarray(j)) then
				test_state = j
				broken_state = j+1
				else if(testarray(j+1)) then
				test_state = j+1
				broken_state = j
!always broken
				else
				test_state = -1
				broken_state = j
				end if !which state
!Only trigger event once for saving the bond atoms
				if (.not.have_break) then
				nbreak_bnd = nbreak_bnd + 1
				break_bonds(nbreak_bnd)%i=qbnd(i)%i
				break_bonds(nbreak_bnd)%j=qbnd(i)%j
				break_bonds(nbreak_bnd)%brk_state=broken_state
				break_bonds(nbreak_bnd)%set_state=test_state
				have_break = .true.
				end if ! have_break
				if((test_state .ne. -1 ) .and.(qbondlib(qbnd(i)%cod(test_state))%Dmz .eq. 0 )) then
!we have a breaking bond set as harmonic
				write(*,227) qbnd(i),qbnd(i)%cod(test_state)
				write(*,228) qbnd(i)%i,qbnd(i)%j
				write(*,225) test_state,qbondlib(test_state)%Dmz,qbondlib(test_state)%amz, qbondlib(test_state)%r0
				write(*,226) test_state, qbondlib(test_state)%r0, qbondlib(test_state)%fk
227		format('WARNING: Breaking/Forming bond',2x,i6,2x,'code',2x,i6,2x,'set as harmonic')
228		format('between atoms',2x,i6,2x,i6)
				end if ! bond is bad
				end if ! bond is breaking
			end do
		end do

160		format (/,'No. of changing bonds    = ',i5)
161		format('atom_i atom_j   bond type in',6(1x,a5,i2))
162		format(i6,1x,i6,t29,6i8)
	end if
	if (allocated(type_read)) then
	    deallocate(type_read)
	end if


	! --- Set new angles
	section = 'angle_types'
	nqacod = prm_max_enum(section, type_count)
	if ( nqacod .gt. 0 ) then
		allocate(type_read(nqacod))
	type_read(:) = .false.
		allocate(qanglib(nqacod))
		!set optional params to 0
		qanglib(:)%ureyfk = 0.0_prec
		qanglib(:)%ureyr0 = 0.0_prec
		write (*,'(/,a)') 'Q-angle types:'
		write (*,'(a)', advance='no') 'type #       force-k   theta0'
		do i=1,type_count
			if(.not. prm_get_line(line)) goto 1000
			read(line,*, iostat=filestat) j, qanglib(j)
			if(filestat == 0) then
				if(i == 1) write(*,'(a)') '  Urey-Bradley force-k      r0'
				type_read(j) = .true.
				write (*,230) j,qanglib(j)
			elseif(filestat < 0) then
				if(i == 1) write(*,*)
				type_read(j) = .true.
				write (*,225) j,qanglib(j)%fk, qanglib(j)%ang0
			else
				goto 1000
			end if
			qanglib(j)%ang0 = deg2rad*qanglib(j)%ang0
		end do
		write (*,*)
	end if

230	format(i6,2f8.2,14x,2f8.2)

	section = 'change_angles'
	nqangle = prm_count(section)
	if(nqangle > 0) then
		write (*,260) nqangle
260		format (/,'No. of changing angles   = ',i5)
		write(*,261) ('state',i,i=1,nstates)
		allocate(qang(nqangle))

		do i=1,nqangle
			if(.not. prm_get_line(line)) goto 1000
			read(line,*, err=1000) qang(i)%i,qang(i)%j,qang(i)%k, qang(i)%cod(1:nstates)
			qang(i)%i = qang(i)%i + offset
			qang(i)%j = qang(i)%j + offset
			qang(i)%k = qang(i)%k + offset
			write (*,262) qang(i)%i,qang(i)%j,qang(i)%k, qang(i)%cod(1:nstates)
			!check types
			do j=1,nstates
				if(qang(i)%cod(j) > 0) then
					if (allocated(type_read)) then
					if(.not. type_read(qang(i)%cod(j))) then
						write(*,112) 'Q-angle', qang(i)%cod(j)
						qatom_load_fep = .false.
					end if
					else
					    write(*,112) 'Q-angle', qang(i)%cod(j)
					    qatom_load_fep = .false.
					end if
				end if
			end do !j
		end do !i
261		format('atom_i atom_j atom_k    angle type in',5(1x,a5,i2))
262		format(i6,1x,i6,1x,i6,t38,5i8)
	end if
	if (allocated(type_read)) then
	    deallocate(type_read)
	end if


!Add section to check angles for being broken with bonds
!first get atoms that are breaking bonds
!then get the angles that those atoms are involved in if not set to zero
!and check if they are broken in the angles section
!allocate the maximum number of angles that can theoretically break
	allocate(break_angles(nqangle+1),stat=alloc_status_qat)
	call check_alloc_general(alloc_status_qat,'Q angle break array')
	nbreak_ang = 0
	do i=1,nbreak_bnd
		ibreak = break_bonds(i)%i
		jbreak = break_bonds(i)%j
		istate = break_bonds(i)%brk_state
		jstate = break_bonds(i)%set_state
		do j=1,nangles
			if(((ang(j)%i.eq.ibreak .and. ang(j)%j.eq.jbreak) .or. &
				(ang(j)%j.eq.ibreak .and. ang(j)%k.eq.jbreak) .or. &
				(ang(j)%k.eq.ibreak .and. ang(j)%j.eq.jbreak) .or. &
				(ang(j)%j.eq.ibreak .and. ang(j)%i.eq.jbreak)) .and. &
				ang(j)%cod.ne.0) then
				nbreak_ang = nbreak_ang + 1
				break_angles(nbreak_ang)%num = j
				break_angles(nbreak_ang)%code = ang(j)%cod
				break_angles(nbreak_ang)%brk_state = istate
				break_angles(nbreak_ang)%set_state = jstate
				break_angles(nbreak_ang)%i = ang(j)%i
				break_angles(nbreak_ang)%j = ang(j)%j
				break_angles(nbreak_ang)%k = ang(j)%k
			end if
		end do
	end do
!Now we know all the angles that should be broken/not existing
!in the relevant states, but not checking for those that should be there
!loop over the angles that should be gone to make sure they are gone!
!If not, nuke them from orbit, by first setting new qangletype
!and then do the nuking part
	do i=1,nbreak_ang
		ibreak = break_angles(i)%i
		jbreak = break_angles(i)%j
		kbreak = break_angles(i)%k
		istate = break_angles(i)%brk_state
		jstate = break_angles(i)%set_state
		abreak = break_angles(i)%num
		cbreak = break_angles(i)%code
		angle_set = .false.
		do j=1,nqangle
			if(( (ang(abreak)%i.eq.qang(j)%i) .and. (ang(abreak)%j.eq.qang(j)%j) .and. &
				(ang(abreak)%k.eq.qang(j)%k)) .or. &
				( (ang(abreak)%i.eq.qang(j)%k) .and. (ang(abreak)%j.eq.qang(j)%j) .and. &
				(ang(abreak)%k.eq.qang(j)%i))) then 
!angle is set in FEP file, trigger angle_set event
				angle_set = .true.
				if(qang(j)%cod(istate).ne.0) then
!We have a broken angle with non zero angle code in the FEP file
!alert the user, but keep the angle, maybe they will need it
				write(*,263) 
				write(*,264) ibreak,jbreak,kbreak
				write(*,265) istate,qang(j)%cod(istate)
263		format('!!!WARNING!!! Angle to broken bond is not set to zero!!')
264		format('between atoms',2x,i6,2x,i6,2x,i6)
265		format('in state',2x,i6,2x,'qangle code',2x,i6)
				end if ! angle is not set to zero
			end if ! angle is qangle
		end do
		if (.not. angle_set) then
!angle is breaking but not set in FEP file
!critical error, need to add angle to angle list
!with parameters from topology -> needs some ugly hacks
			write(*,263)
			write(*,264) ibreak,jbreak,kbreak
			write(*,266) istate,abreak,cbreak
266		format('in state',2x,i6,2x,'angle',2x,i6,2x,'angle code',2x,i6)
			write(*,267)
                        267		format('Trying to get parameters from Topology for error fixing! Program will terminate!')
!make temporary list of qangle types 
!make sure there are angles set, could be none
!user error avoided
			if (nqacod > 0 ) then
			allocate(tmp_qanglib(nqacod),stat=alloc_status_qat)
			call check_alloc_general(alloc_status_qat,'Allocating tmp qangle code lib')
			tmp_qanglib(1:nqacod)=qanglib(1:nqacod)
!remove old qanqlib
			if (allocated(qanglib)) then
			deallocate(qanglib)
			end if
			end if
!now allocate new qanglib with nqacod+1
			allocate(qanglib(nqacod+1),stat=alloc_status_qat)
			call check_alloc_general(alloc_status_qat,'Allocating new qangle code lib')
			qanglib(:)%ureyfk = 0.0_prec
                        qanglib(:)%ureyr0 = 0.0_prec
!if the old library is there, copy it into the new array
			if (allocated(tmp_qanglib)) then
			qanglib(1:nqacod)=tmp_qanglib(1:nqacod)
			deallocate(tmp_qanglib)
			end if
!now set the new qangle type from the topology
			qanglib(nqacod+1)%fk = anglib(cbreak)%fk
			qanglib(nqacod+1)%ang0 = anglib(cbreak)%ang0
			qanglib(nqacod+1)%ureyfk = anglib(cbreak)%ureyfk
			qanglib(nqacod+1)%ureyr0 = anglib(cbreak)%ureyr0
			write (*,'(a)', advance='no') 'type #       force-k   theta0'
			write (*,225) nqacod+1,qanglib(nqacod+1)%fk, qanglib(nqacod+1)%ang0
!and set new number of qangles to nqacod+1
			nqacod = nqacod + 1
!we have the angle type, add it to the number of active qangles
!with no angle in the broken state
!first, again need to reallocate the qangles
			if (nqangle > 0 ) then
			allocate(tmp_qang(nqangle),stat=alloc_status_qat)
			call check_alloc_general(alloc_status_qat,'Allocating tmp qangle lib')
			tmp_qang(1:nqangle)=qang(1:nqangle)
			deallocate(qang)
			end if
			allocate(qang(nqangle+1),stat=alloc_status_qat)
			call check_alloc_general(alloc_status_qat,'Allocating new qangle lib')
			if (allocated(tmp_qang)) then
			qang(1:nqangle)=tmp_qang(1:nqangle)
			deallocate(tmp_qang)
			end if
			qang(nqangle+1)%i = ibreak
			qang(nqangle+1)%j = jbreak
			qang(nqangle+1)%k = kbreak
			qang(nqangle+1)%cod(:) = 0
!if angle is always broken, keep it like that
			if (jstate .ne. -1 ) then
			qang(nqangle+1)%cod(jstate) = nqacod
			end if
			nqangle = nqangle + 1
			write(*,261) ('state',ii,ii=1,nstates)
                        write (*,262) qang(nqangle)%i,qang(nqangle)%j,qang(nqangle)%k, qang(nqangle)%cod(1:nstates)
                        qatom_load_fep = .false.
		end if
	end do
	if(allocated(break_angles)) then
	deallocate(break_angles)
	end if

  ! --- Set new torsions
	section = 'torsion_types'
	nqtcod = prm_max_enum(section, type_count)
	allocate(qtorlib(nqtcod),stat=alloc_status_qat)
	call check_alloc_general(alloc_status_qat,'Allocating qtorsion library array')
	if ( nqtcod .gt. 0 ) then
		allocate(type_read(nqtcod))
		type_read(:) = .false.
		write (*,350)
		do i=1,type_count
			if(.not. prm_get_line(line)) goto 1000
			read(line,*, err=1000) j, qtorlib(j)%fk, qtorlib(j)%rmult,qtorlib(j)%deltor
			type_read(j) = .true.
			write (*,225) j,qtorlib(j)%fk, qtorlib(j)%rmult,qtorlib(j)%deltor
			qtorlib(j)%deltor = deg2rad*qtorlib(j)%deltor
		end do
		write (*,*)
	end if
350	format(/,'Q-torsion types:',/,'type #       force-k     mult    delta')
	section='change_torsions'
	nqtor = prm_count(section)
	if(nqtor > 0) then
		write (*,360) nqtor
		write(*,361) ('state',i,i=1,nstates)
360		format (/,'No. of changing torsions = ',i5)
		allocate(qtor(nqtor),stat=alloc_status_qat)
		call check_alloc_general(alloc_status_qat,'Allocating qtorsion array')

		do i=1,nqtor
			if(.not. prm_get_line(line)) goto 1000
			read(line,*, err=1000) qtor(i)%i,qtor(i)%j,qtor(i)%k,qtor(i)%l,qtor(i)%cod(1:nstates)
			qtor(i)%i = qtor(i)%i + offset
			qtor(i)%j = qtor(i)%j + offset
			qtor(i)%k = qtor(i)%k + offset
			qtor(i)%l = qtor(i)%l + offset
			write (*,362) qtor(i)%i,qtor(i)%j,qtor(i)%k,qtor(i)%l,qtor(i)%cod(1:nstates)
			!check types
			do j=1,nstates
                                if(qtor(i)%cod(j) > 0) then
					if (allocated(type_read)) then
                                        if(.not. type_read(qtor(i)%cod(j))) then
                                                write(*,112) 'Q-torsion', qtor(i)%cod(j)
						qatom_load_fep = .false.
					end if
					else
                                            write(*,112) 'Q-torsion', qtor(i)%cod(j)
					    qatom_load_fep = .false.
					end if
				end if
			end do !j
		end do !i
361	format('atom_i atom_j atom_k atom_l    torsion type in',4(1x,a5,i2))
362	format(4(i6,1x),t47,4i8)
	end if
	if (allocated(type_read)) then
	    deallocate(type_read)
	end if

!Add section to check torsion for being broken with bonds
!first get atoms that are breaking bonds
!then get the torsions that those atoms are involved in if not set to zero
!and check if they are broken in the torsion section
!allocate the maximum number of torsions that can theoretically break
        allocate(break_torsions(nqtor+1),stat=alloc_status_qat)
	call check_alloc_general(alloc_status_qat,'Q torsion breaking array')
	nbreak_tor=0
        do i=1,nbreak_bnd
                ibreak = break_bonds(i)%i
                jbreak = break_bonds(i)%j
                istate = break_bonds(i)%brk_state
                jstate = break_bonds(i)%set_state
                do j=1,ntors
                        if(((tor(j)%i.eq.ibreak .and. tor(j)%j.eq.jbreak) .or. &
                                (tor(j)%j.eq.ibreak .and. tor(j)%k.eq.jbreak) .or. &
				(tor(j)%k.eq.ibreak .and. tor(j)%l.eq.jbreak) .or. &
				(tor(j)%l.eq.ibreak .and. tor(j)%k.eq.jbreak) .or. &
                                (tor(j)%k.eq.ibreak .and. tor(j)%j.eq.jbreak) .or. &
                                (tor(j)%j.eq.ibreak .and. tor(j)%i.eq.jbreak)) .and. &
                                tor(j)%cod.ne.0) then
                                nbreak_tor = nbreak_tor + 1
                                break_torsions(nbreak_tor)%num = j
                                break_torsions(nbreak_tor)%code = tor(j)%cod
                                break_torsions(nbreak_tor)%brk_state = istate
                                break_torsions(nbreak_tor)%set_state = jstate
                                break_torsions(nbreak_tor)%i = tor(j)%i
                                break_torsions(nbreak_tor)%j = tor(j)%j
                                break_torsions(nbreak_tor)%k = tor(j)%k
				break_torsions(nbreak_tor)%l = tor(j)%l
                        end if
                end do
        end do
!Now we know all the torsions that should be broken/not existing
!in the relevant states, but not checking for those that should be there
!loop over the torsions that should be gone to make sure they are gone!
!If not, nuke them from orbit, by first setting new qtorsiontype
!and then do the nuking part
        do i=1,nbreak_tor
                ibreak = break_torsions(i)%i
                jbreak = break_torsions(i)%j
                kbreak = break_torsions(i)%k
		lbreak = break_torsions(i)%l
                istate = break_torsions(i)%brk_state
                jstate = break_torsions(i)%set_state
                abreak = break_torsions(i)%num
                cbreak = break_torsions(i)%code
                torsion_set = .false.
                do j=1,nqtor
                        if((tor(abreak)%i.eq.qtor(j)%i) .and. (tor(abreak)%j.eq.qtor(j)%j) .and. &
                                (tor(abreak)%k.eq.qtor(j)%k) .and. (tor(abreak)%l.eq.qtor(j)%l) .or. &
                                ((tor(abreak)%i.eq.qtor(j)%l) .and. (tor(abreak)%j.eq.qtor(j)%k) .and. &
                                (tor(abreak)%k.eq.qtor(j)%j) .and. (tor(abreak)%l.eq.qtor(j)%i))) then
!torsion is set in FEP file, trigger torsion_set event
                                torsion_set = .true.
                                if(qtor(j)%cod(istate).ne.0) then
!We have a broken torsion with non zero torsion code in the FEP file
!alert the user, but keep the torsion, maybe they will need it
                                write(*,363)
                                write(*,364) ibreak,jbreak,kbreak,lbreak
                                write(*,365) istate,qtor(j)%cod(istate)
363             format('!!!WARNING!!! Torsion to broken bond is not set to zero!!')
364             format('between atoms',2x,i6,2x,i6,2x,i6,2x,i6)
365             format('in state',2x,i6,2x,'qtor code',2x,i6)
                                end if ! torsion is not set to zero
                        end if ! torsion is qtor
                end do
                if (.not. torsion_set) then
!torsion is breaking but not set in FEP file
!critical error, need to add torsion to qtorsion list
!with parameters from topology -> needs some ugly hacks
                        write(*,363)
                        write(*,364) ibreak,jbreak,kbreak,lbreak
                        write(*,366) istate,abreak,cbreak
366             format('in state',2x,i6,2x,'torsion',2x,i6,2x,'torsion code',2x,i6)
                        write(*,267)
!make temporary list of qtor types
!make sure there are torsions set, could be none
!user error avoided
                        if (nqtcod > 0 ) then
                        allocate(tmp_qtorlib(nqtcod),stat=alloc_status_qat)
                        call check_alloc_general(alloc_status_qat,'Allocating tmp qtor code lib')
                        tmp_qtorlib(1:nqtcod)=qtorlib(1:nqtcod)
!remove old qtorlib
                        deallocate(qtorlib)
                        end if
!now allocate new qtorlib with nqtcod+1
                        allocate(qtorlib(nqtcod+1),stat=alloc_status_qat)
                        call check_alloc_general(alloc_status_qat,'Allocating new qtor code lib')
!if the old library is there, copy it into the new array
                        if (allocated(tmp_qtorlib)) then
                        qtorlib(1:nqtcod)=tmp_qtorlib(1:nqtcod)
                        deallocate(tmp_qtorlib)
                        end if
!now set the new qtor type from the topology
                        qtorlib(nqtcod+1)%fk = torlib(cbreak)%fk
			qtorlib(nqtcod+1)%rmult = torlib(cbreak)%rmult
			qtorlib(nqtcod+1)%deltor = torlib(cbreak)%deltor
	                write (*,350)
                        write (*,225) nqtcod+1,qtorlib(nqtcod+1)%fk, qtorlib(nqtcod+1)%rmult,qtorlib(nqtcod+1)%deltor
!and set new number of qtorlib to nqtcod+1
                        nqtcod = nqtcod + 1
!we have the torsion type, add it to the number of active qtorsions
!with no torsion in the broken state
!first, again need to reallocate the qtorsions
                        if (nqtor > 0 ) then
                        allocate(tmp_qtor(nqtor),stat=alloc_status_qat)
                        call check_alloc_general(alloc_status_qat,'Allocating tmp qtor lib')
                        tmp_qtor(1:nqtor)=qtor(1:nqtor)
                        deallocate(qtor)
                        end if
                        allocate(qtor(nqtor+1),stat=alloc_status_qat)
                        call check_alloc_general(alloc_status_qat,'Allocating new qtor list')
                        if (allocated(tmp_qtor)) then
                        qtor(1:nqtor)=tmp_qtor(1:nqtor)
                        deallocate(tmp_qtor)
                        end if
                        qtor(nqtor+1)%i = ibreak
                        qtor(nqtor+1)%j = jbreak
                        qtor(nqtor+1)%k = kbreak
			qtor(nqtor+1)%l = lbreak
                        qtor(nqtor+1)%cod(:) = 0
			if (jstate .ne. -1 ) then
			end if
                        qtor(nqtor+1)%cod(jstate) = nqtcod
	                write(*,361) ('state',ii,ii=1,nstates)
                        write (*,362) qtor(nqtor+1)%i,qtor(nqtor+1)%j,qtor(nqtor+1)%k,qtor(nqtor+1)%l,qtor(nqtor+1)%cod(1:nstates)
                        nqtor = nqtor + 1
                        qatom_load_fep =.false.
                end if
        end do
	if(allocated(break_torsions)) then
	deallocate(break_torsions)
	end if
	! --- Set new impropers
	section='improper_types'
	nqicod=prm_max_enum(section, type_count)
	if(nqicod > 0 ) then
		allocate(type_read(nqicod))
	type_read(:) = .false.
		allocate(qimplib(nqicod),stat=alloc_status_qat)
		call check_alloc_general(alloc_status_qat,'Q improper library array')
		write (*,450)
450	format(/,'Q-improper types:',/,'type #       force-k     imp0')
		do i=1,nqicod
			if(.not. prm_get_line(line)) goto 1000
			read(line,*, err=1000) j, qimplib(j)%fk,qimplib(j)%imp0
			type_read(j) = .true.
			write(*,225) j,qimplib(j)%fk,qimplib(j)%imp0
			qimplib(j)%imp0 = deg2rad*qimplib(j)%imp0
		end do
		write (*,*)
	end if

	section = 'change_impropers'
	nqimp = prm_count(section)
	if(nqimp > 0) then
		write (*,460) nqimp
460		format (/,'No. of changing impropers= ',i5)
		write(*,461) ('state',i,i=1,nstates)
		allocate(qimp(nqimp),stat=alloc_status_qat)
		call check_alloc_general(alloc_status_qat,'Q improper array')

		do i=1,nqimp
			if(.not. prm_get_line(line)) goto 1000
			read(line,*, err=1000) qimp(i)%i,qimp(i)%j,qimp(i)%k,qimp(i)%l,qimp(i)%cod(1:nstates)
			qimp(i)%i = qimp(i)%i + offset
			qimp(i)%j = qimp(i)%j + offset
			qimp(i)%k = qimp(i)%k + offset
			qimp(i)%l = qimp(i)%l + offset
			write (*,462) qimp(i)%i,qimp(i)%j,qimp(i)%k,qimp(i)%l,qimp(i)%cod(1:nstates)
			!check types
			do j=1,nstates
                                if(qimp(i)%cod(j) > 0) then
					if (allocated(type_read)) then
                                        if(.not. type_read(qimp(i)%cod(j))) then
                                                write(*,112) 'Q-improper', qimp(i)%cod(j)
						qatom_load_fep = .false.
					end if
					else
                                            write(*,112) 'Q-improper', qimp(i)%cod(j)
					    qatom_load_fep = .false.
					end if
				end if
			end do !j
		end do !i
	end if
461	format('atom_i atom_j atom_k atom_l    improper type in',4(1x,a5,i2))
462	format(4(i6,1x),t48,4i8)
!Add section to check improper torsion for being broken with bonds
!first get atoms that are breaking bonds
!then get the torsions that those atoms are involved in if not set to zero
!and check if they are broken in the improper section
!allocate the maximum number of impropers that can theoretically break
        allocate(break_impropers(nqimp+1),stat=alloc_status_qat)
	call check_alloc_general(alloc_status_qat,'Q improper breaking array')
	nbreak_imp = 0
        do i=1,nbreak_bnd
                ibreak = break_bonds(i)%i
                jbreak = break_bonds(i)%j
                istate = break_bonds(i)%brk_state
                jstate = break_bonds(i)%set_state
                do j=1,nimps
			if( ( (imp(j)%i.eq.ibreak .and. imp(j)%j.eq.jbreak) .or. &
				(imp(j)%i.eq.ibreak .and. imp(j)%j.eq.ibreak) .or. &
				(imp(j)%j.eq.ibreak .and. imp(j)%k.eq.jbreak) .or. &
				(imp(j)%k.eq.ibreak .and. imp(j)%j.eq.jbreak) .or. &
				(imp(j)%j.eq.ibreak .and. imp(j)%l.eq.jbreak) .or. &
				(imp(j)%l.eq.ibreak .and. imp(j)%j.eq.jbreak)) .and. &
				imp(j)%cod.ne.0) then
                                nbreak_imp = nbreak_imp + 1
                                break_impropers(nbreak_imp)%num = j
                                break_impropers(nbreak_imp)%code = imp(j)%cod
                                break_impropers(nbreak_imp)%brk_state = istate
                                break_impropers(nbreak_imp)%set_state = jstate
                                break_impropers(nbreak_imp)%i = imp(j)%i
                                break_impropers(nbreak_imp)%j = imp(j)%j
                                break_impropers(nbreak_imp)%k = imp(j)%k
                                break_impropers(nbreak_imp)%l = imp(j)%l
                        end if
                end do
        end do


!Now we know all the improper torsions that should be broken/not existing
!in the relevant states, but not checking for those that should be there
!loop over the impropers that should be gone to make sure they are gone!
!If not, nuke them from orbit, by first setting new qtorsiontype
!and then do the nuking part
        do i=1,nbreak_imp
                ibreak = break_impropers(i)%i
                jbreak = break_impropers(i)%j
                kbreak = break_impropers(i)%k
                lbreak = break_impropers(i)%l
                istate = break_impropers(i)%brk_state
                jstate = break_impropers(i)%set_state
                abreak = break_impropers(i)%num
                cbreak = break_impropers(i)%code
                improper_set = .false.
                do j=1,nqimp
                        if(( (imp(abreak)%i.eq.qimp(j)%i) .and. (imp(abreak)%j.eq.qimp(j)%j) .and. &
                                (imp(abreak)%k.eq.qimp(j)%k) .and. (imp(abreak)%l.eq.qimp(j)%l)) .or. &
				((imp(abreak)%i.eq.qimp(j)%k) .and. (imp(abreak)%j.eq.qimp(j)%j) .and. &
				(imp(abreak)%k.eq.qimp(j)%i) .and. (imp(abreak)%l.eq.qimp(j)%l)) .or. &
				((imp(abreak)%i.eq.qimp(j)%k) .and. (imp(abreak)%j.eq.qimp(j)%j) .and. &
				(imp(abreak)%k.eq.qimp(j)%l) .and. (imp(abreak)%l.eq.qimp(j)%i)) .or. &
				((imp(abreak)%i.eq.qimp(j)%l) .and. (imp(abreak)%j.eq.qimp(j)%j) .and. &
				(imp(abreak)%k.eq.qimp(j)%i) .and. (imp(abreak)%l.eq.qimp(j)%k)) .or. &
				((imp(abreak)%i.eq.qimp(j)%l) .and. (imp(abreak)%j.eq.qimp(j)%j) .and. &
				(imp(abreak)%k.eq.qimp(j)%k) .and. (imp(abreak)%l.eq.qimp(j)%i))) then
!improper is set in FEP file, trigger improper_set event
                                improper_set = .true.
                                if(qimp(j)%cod(istate).ne.0) then
!We have a broken improper with non zero improper code in the FEP file
!alert the user, but keep the improper, maybe they will need it
                                write(*,463)
                                write(*,364) ibreak,jbreak,kbreak,lbreak
                                write(*,365) istate,qtor(j)%cod(istate)
463             format('!!!WARNING!!! Improper to broke bond is not set to zero!!')
                                end if ! improper is not set to zero
                        end if ! improper is qimp
                end do
                if (.not. improper_set) then
!improper is breaking but not set in FEP file
!critical error, need to add improper torsion to qimp list
!with parameters from topology -> needs some ugly hacks
                        write(*,363)
                        write(*,364) ibreak,jbreak,kbreak,lbreak
                        write(*,466) istate,abreak,cbreak
466             format('in state',2x,i6,2x,'improper',2x,i6,2x,'improper code',2x,i6)
                        write(*,267)
!make temporary list of qimp types
!make sure there are impropers set, could be none
!user error avoided
                        if (nqicod > 0 ) then
                        allocate(tmp_qimplib(nqicod),stat=alloc_status_qat)
                        call check_alloc_general(alloc_status_qat,'Allocating tmp qimp code lib')
                        tmp_qimplib(1:nqicod)=qimplib(1:nqicod)
!remove old qimplib
                        deallocate(qimplib)
                        end if
!now allocate new qimplib with nqicod+1
                        allocate(qimplib(nqicod+1),stat=alloc_status_qat)
                        call check_alloc_general(alloc_status_qat,'Allocating new qimp code lib')
!if the old library is there, copy it into the new array
                        if (allocated(tmp_qimplib)) then
                        qimplib(1:nqicod)=tmp_qimplib(1:nqicod)
                        deallocate(tmp_qimplib)
                        end if
!now set the new qimp type from the topology
                        qimplib(nqicod+1)%fk = implib(cbreak)%fk
                        qimplib(nqicod+1)%imp0 = implib(cbreak)%imp0
	                write (*,450)
                        write(*,225) nqicod + 1,qimplib(nqicod + 1)%fk,qimplib(nqicod + 1)%imp0
!and set new number of qimplib to nqicod+1
                        nqicod = nqicod + 1
!we have the improper type, add it to the number of active qimpropers
!with no improper in the broken state
!first, again need to reallocate the qimpropers
                        if (nqimp > 0 ) then
                        allocate(tmp_qimp(nqimp),stat=alloc_status_qat)
                        call check_alloc_general(alloc_status_qat,'Allocating tmp qimp lib')
                        tmp_qimp(1:nqimp)=qimp(1:nqimp)
                        deallocate(qimp)
                        end if
                        allocate(qimp(nqimp+1),stat=alloc_status_qat)
                        call check_alloc_general(alloc_status_qat,'Allocating new qimp list')
                        if (allocated(tmp_qimp)) then
                        qimp(1:nqimp)=tmp_qimp(1:nqimp)
                        deallocate(tmp_qimp)
                        end if
                        qimp(nqimp+1)%i = ibreak
                        qimp(nqimp+1)%j = jbreak
                        qimp(nqimp+1)%k = kbreak
                        qimp(nqimp+1)%l = lbreak
                        qimp(nqimp+1)%cod(:) = 0
			if (jstate .ne. -1 ) then
                        qimp(nqimp+1)%cod(jstate) = nqicod
			end if
	                write(*,461) ('state',ii,ii=1,nstates)
                        write (*,462) qimp(nqimp+1)%i,qimp(nqimp+1)%j,qimp(nqimp+1)%k,qimp(nqimp+1)%l,qimp(nqimp+1)%cod(1:nstates)
                        nqimp = nqimp + 1
                        qatom_load_fep = .false.
                end if
        end do
        if(allocated(break_impropers)) then
        deallocate(break_impropers)
        end if
	if (allocated(type_read)) then
	    deallocate(type_read)
	end if

  ! --- Read angle,torsion and improper couplings to Morse bonds
	section = 'angle_couplings'
	nang_coupl = prm_count(section)
	if(nang_coupl > 0) then
		write (*,544) nang_coupl
544		format (/,'No. of angle-Morse couplings = ',i5)
		write(*,543)
		do i=1,nang_coupl
                        if(.not. prm_get_line(line))  goto 1000
                        read(line,*,iostat=stat) j,k,l
                        if(stat .eq.0) then
                                iang_coupl(1,i) = j
                                iang_coupl(2,i) = k
                                iang_coupl(3,i) = l
                        else
                                read(line,*,err=1000) j,k
                                iang_coupl(1,i) = j
                                iang_coupl(2,i) = k
                                iang_coupl(3,i) = 0
                        end if
			write (*,545) iang_coupl(:,i)
			if(j < 1 .or. j > nqangle) then
				write(*,546) 'q-angle', j
				qatom_load_fep = .false.
			end if
			if(k < 1 .or. k > nqbond) then
				write(*,546) 'q-bond', k
				qatom_load_fep = .false.
			end if
			if(bond_harmonic_in_any_state(k)) then
                                write(*,'(a,i6,a)') '>>>> ERROR: q-bond ',k,' is always harmonic'
				qatom_load_fep = .false.
			end if
		end do
	end if
543	format ('angle_i bond_j')
545	format(i7,1x,i6)
546	format('>>>>> ERROR: ',a,' number ',i2,' does not exist.')

	section='torsion_couplings'
	ntor_coupl=prm_count(section)
	if( ntor_coupl > 0) then
		write (*,548) ntor_coupl
548		format (/,'No. of torsion-Morse couplings = ',i5)
		write(*,547)
		do i=1,ntor_coupl
                        if(.not.prm_get_line(line)) goto 1000
                        read(line,*,iostat=stat) j,k,l
                        if(stat .eq. 0) then
                                itor_coupl(1,i) = j
                                itor_coupl(2,i) = k
                                itor_coupl(3,i) = l
                        else
                                read(line,*,err=1000) j,k
                                itor_coupl(1,i) = j
                                itor_coupl(2,i) = k
                                itor_coupl(3,i) = 0
                        end if
			write (*,549) itor_coupl(:,i)
			if(j < 1 .or. j > nqtor) then
				write(*,546) 'q-torsion', j
				qatom_load_fep = .false.
			end if
			if(k < 1 .or. k > nqbond) then
				write(*,546) 'q-bond', k
				qatom_load_fep = .false.
			end if
			if(bond_harmonic_in_any_state(k)) then
                                write(*,'(a,i6,a)') '>>>> ERROR: q-bond ',k,' is always harmonic'
				qatom_load_fep = .false.
			end if
		end do
547	format ('torsion_i bond_j')
549	format (i9,1x,i6)
	end if

	section='improper_couplings'
	nimp_coupl=prm_count(section)

	if(nimp_coupl > 0 ) then
		write (*,552) nimp_coupl
552		format (/,'No. of improper-Morse couplings = ',i5)
		write(*,554)
		do i=1,nimp_coupl
		    if (.not. prm_get_line(line)) goto 1000
			read(line,*, iostat=stat) j,k,l
			if(stat .eq. 0) then
				iimp_coupl(1,i) = j
				iimp_coupl(2,i) = k
				iimp_coupl(3,i) = l
			else
				read(line,*, err=1000) j, k
				iimp_coupl(1,i) = j
				iimp_coupl(2,i) = k
				iimp_coupl(3,i) = 0
			end if

			write (*,553) iimp_coupl(:,i)
			if(j < 1 .or. j > nqimp) then
				write(*,546) 'q-improper', j
				qatom_load_fep = .false.
			end if
			if(k < 1 .or. k > nqbond) then
				write(*,546) 'q-bond', j
				qatom_load_fep = .false.
			end if
			if(bond_harmonic_in_any_state(k)) then
                                write(*,'(a,i6,a)') '>>>> ERROR: q-bond ',k,' is always harmonic'
				qatom_load_fep = .false.
			end if
		end do
	end if
554	format ('improper_i bond_j making/breaking')
553	format (i10,1x,i6,1x,i15)

	! --- Read extra shake constraints
	section='shake_constraints'
	nqshake=prm_count(section)
	if(nqshake > 0) then
		write (*,560) nqshake, ('state',i,i=1,nstates)
560		format (/,'No. of fep/evb shake contraints = ',i5,/ &
				'atom_i atom_j    distance in',5(1x,a5,i2))
		do i=1,nqshake
			if(.not. prm_get_line(line)) goto 1000
			read(line,*, err=1000) iqshake(i),jqshake(i),qshake_dist(i,1:nstates)
			iqshake(i) = iqshake(i) + offset
			jqshake(i) = jqshake(i) + offset
			write (*,580) iqshake(i),jqshake(i),qshake_dist(i,1:nstates)
		end do
580		format (i6,1x,i6,t29,5f8.2)
	end if

  ! --- Read off-diagonal hamiltonial matrix functions
	section = 'off_diagonals'
	noffd = prm_count(section)
	!always allocate (needed for energy file writing)
	allocate(offd(noffd), offd2(noffd))
	if(noffd > 0) then
		write (*,600) noffd
600		format (/,'No. of offdiagonal (Hij) functions = ',i5)
		if(noffd > max_states) then
			write(*,'(a,i2,a)') &
				'>>> Error: Too many off-diagonal functions, (max_states is ', &
				max_states, ' Aborting.'
			qatom_load_fep = .false.
			call prm_close
			return
		end if
		write (*,'(a)') 'state_i state_j atom_k atom_l     Aij mu_ij'

		do i=1,noffd
			if(.not. prm_get_line(line)) goto 1000
			read(line,*, err=1000) offd(i)%i,offd(i)%j,offd2(i)%k, &
				offd2(i)%l,offd2(i)%A, offd2(i)%mu
			write (*,620) offd(i)%i,offd(i)%j,offd2(i)%k,&
				offd2(i)%l,offd2(i)%A, offd2(i)%mu
			!check states
			if(offd(i)%i < 1 .or. offd(i)%i > nstates .or. &
				offd(i)%j < 1 .or. offd(i)%j > nstates .or. &
				offd(i)%i == offd(i)%j) then
				write(*,622)
				qatom_load_fep = .false.
			end if
			!check q-atom numbers
			if(offd2(i)%k < 1 .or. offd2(i)%k > nqat .or. &
				offd2(i)%l < 1 .or. offd2(i)%l > nqat) then
				write(*,148) offd2(i)%k, offd2(i)%l
				qatom_load_fep = .false.
			else if(iqseq(offd2(i)%k) == 0 .or. iqseq(offd2(i)%l) == 0) then
				write(*,148) offd2(i)%k,offd2(i)%l
				qatom_load_fep = .false.
			end if
		end do
	end if
620	format (i7,1x,3i7,f8.2,f6.2)
622	format('>>>>> ERROR: Invalid combination of states: ',2i5)

	!************Softcore section************  MPA
	if (allocated(sc_lookup))    deallocate (sc_lookup)
	allocate (alpha_max(nqat,nstates),sc_lookup(nqat,natyps+nqat,nstates))

	!default is no softcore, i.e. alpha=zero (sc_lookup = 0)
	sc_lookup(:,:,:)=zero

	section = 'softcore'
	if(.not. prm_open_section(section)) then
		write (*,1630)
	else
		write(*,'(a)') 'Reading softcore section'
		if(.not. qvdw_flag) then
			write(*,'(a)') '>>>>> ERROR: Q-atom types must be redefined in "change_atoms" section'
			qatom_load_fep = .false.
			return
		end if

		numsoftlines = prm_count(section)
		if(numsoftlines /= nqat) then
			write(*,'(a)') '>>>>> ERROR: Alpha must be given for every Q-atom!'
			qatom_load_fep = .false.
			return
		else
			write (*,1625)
1625			format (/,'Assigning softcore to all Q atoms:')
1626			format('Q atom    softcore alpha in',6(2x,a5,i2))
1627			format('Q atom      max potenial in',6(2x,a5,i2))

			if (softcore_use_max_potential) then
				write (*,'(a)') ('Using values in FEP file as desired maximum vdW potentials at r=0')
				write (*,1627) ('state',i,i=1,nstates)
			else
				write (*,'(a)') ('Using values in FEP file as explicit alphas')
				write (*,1626) ('state',i,i=1,nstates)
			end if

			do i=1,nqat   !read all the softcore max_alphas
				!reading should not fail at this stage - get_line was called by prm_count!
				if(.not. prm_get_line(line)) goto 1000
				read (line,*, err=1000) tmpindex, alpha_max(tmpindex,1:nstates)

				write (*,'(i6,t25,6(f8.2,1x))') tmpindex, alpha_max(tmpindex,1:nstates)

			end do

			do i=1,nqat  !make the sc_lookup table
				do i2=1,nstates
					do j=1,natyps !do q-surroundings first

						if (softcore_use_max_potential) then
							sc_aq = qavdw(qiac(i,i2),1)
							sc_bq = qbvdw(qiac(i,i2),1)
							sc_aj = iaclib(j)%avdw(1)
							sc_bj = iaclib(j)%bvdw(1)
							if (alpha_max(i,i2) .gt. 1E-6_prec) then
								if (ivdw_rule == 1) then !geometric vdw rule
									sc_lookup(i,j,i2) = (-sc_bq*sc_bj+q_sqrt(sc_bq*sc_bq*sc_bj* &
										sc_bj+4.0_prec*alpha_max(i,i2)*sc_aq*sc_aj))/(2.0_prec*alpha_max(i,i2))
								else !arithmetic vdw rule. OBS some epsilons (q atom epsilons, sc_bq)
										!	have not been square rooted yet. We'll take this into account
										!   when calculating the sc_lookup
									sc_lookup(i,j,i2) = (-2.0_prec*q_sqrt(sc_bq)*sc_bj+2.0_prec*q_sqrt(sc_bq*sc_bj**2+ &
									alpha_max(i,i2)*q_sqrt(sc_bq)*sc_bj))*(sc_aq+sc_aj)**6/(2.0_prec*alpha_max(i,i2))
								end if
							end if
						else  !user has not requested alpha calculation, each q-atom has the same alpha for every atom type
							sc_lookup(i,j,i2) = alpha_max(i,i2)
						end if


					end do

					do j=1,nqat  !now do q-q
						if ((alpha_max(i,i2) .gt. 1E-6_prec) .or. (alpha_max(j,i2) .gt. 1E-6_prec)) then !if both alphas are 0 then no need to calculate alphas
							sc_aq = qavdw(qiac(i,i2),1)
							sc_bq = qbvdw(qiac(i,i2),1)
							sc_aj = qavdw(qiac(j,i2),1)
							sc_bj = qbvdw(qiac(j,i2),1)

							if (softcore_use_max_potential) then  !use the smallest alpha_max of the two q atoms
								alpha_max_tmp = min ( alpha_max(i,i2), alpha_max(j,i2) )

								if ((alpha_max(i,i2) .lt. 1E-6_prec) .or. (alpha_max(j,i2) .lt. 1E-6_prec)) then !unless one of them is zero
									alpha_max_tmp = max ( alpha_max(i,i2), alpha_max(j,i2) )
								end if



							else  !use the largest alpha_max if we're using plain alphas
								alpha_max_tmp = max ( alpha_max(i,i2), alpha_max(j,i2) )
							end if


							if (softcore_use_max_potential) then

								if (ivdw_rule == 1) then !geometric vdw rule
									sc_lookup(i,j+natyps,i2) = (-sc_bq*sc_bj+ &
										q_sqrt(sc_bq*sc_bq*sc_bj*sc_bj+ &
										4.0_prec*alpha_max_tmp*sc_aq*sc_aj))/(2.0_prec*alpha_max_tmp)
								else !arithmetic vdw rule   OBS some epsilons (q atom epsilons, sc_bq and sc_bj)
										!	have not been square-rooted yet. We'll take this into account
										!   when calculating the sc_lookup
									sc_lookup(i,j+natyps,i2) = (-2.0_prec*q_sqrt(sc_bq*sc_bj)+ &
										2.0_prec*q_sqrt(sc_bq*sc_bj+alpha_max_tmp*q_sqrt(sc_bq*sc_bj)))* &
										(sc_aq+sc_aj)**6/(2.0_prec*alpha_max_tmp)
								end if

							else  !user has not requested alpha calculation, each q-atom has the same alpha for every atom type
								sc_lookup(i,j+natyps,i2) = alpha_max_tmp
							end if !softcore_use_max_potential

						end if


					end do





				end do  ! states


			end do !softcore lookup table
		end if
	end if  !prm_open_section(section)   softcore


1630		format('No softcore section found. Using normal LJ potentials.')

	!********END*****Softcore section****END********  MPA

	!load atom groups whose non-bonded interactions are to be monitored
	section='monitor_groups'
	monitor_groups=prm_count(section)
	allocate(monitor_atom_group(monitor_groups))
	if (monitor_groups>0) then
			write (*,650) monitor_groups
			do i=1,monitor_groups
					k=0
					do while(prm_get_field(line)) !get one topology atom number at a time
						k=k+1
						read(line,*) temp_atom(k)   !read line med fritt format
					end do
					allocate(monitor_atom_group(i)%atom(k))   !k är antal element i array nr i
					monitor_atom_group(i)%atom(:)=temp_atom(1:k) + offset! kopiera temp_atom arrayens element med index 1-k till
					monitor_atom_group(i)%n=k
					write (*,660,advance='no') i
					write (*,670) monitor_atom_group(i)%atom(:)
			end do
	end if
650	format (/,'No. atom groups to monitor   = ',i5)
660	format ('group' ,i2, ':')
670	format (7i8)

	section='monitor_group_pairs'
	monitor_group_pairs=prm_count(section)   !antal rader i avd.
	allocate(monitor_group_pair(monitor_group_pairs))
	if(monitor_group_pairs > 0) then
			write (*,*)
			write (*,630) monitor_group_pairs
			write (*,'(a)') 'group_i group_j'
			do i=1,monitor_group_pairs
				if (.not. prm_get_int_int(monitor_group_pair(i)%i, monitor_group_pair(i)%j)) goto 1000   !läser in i arrayen monitor_group_pair
				write (*,640)  monitor_group_pair(i)%i, monitor_group_pair(i)%j
			end do
	end if
630	format (/,'No. of group pairs to monitor= ',i5)
640	format (i7,1x,i7)


! information for QCP atom selection and size allocation
! only use if use_QCP is true at this point, otherwise skip
! numbering is always Q-atom numbers!!!
	if(use_qcp) then
	section='qcp_atoms'
	tmp_qcp_num = prm_count(section)
! remember, QCP atoms will be listed as Q atoms, so use those lists later for searching
! also, makes it easier to assign them in the files
! first check if FEP file redefines QCP atoms
! if list is empty in the end, print big warning and turn of QCP
	if (tmp_qcp_num .gt. 0) then
! redefined
		write (*,'(a)') 'Defining QCP selection in FEP file, overwriting predefined selections!'
		qcp_atnum = tmp_qcp_num
		allocate(qcp_atom(qcp_atnum))
		do i=1,tmp_qcp_num
			if(.not. prm_get_line(line)) goto 1000
			read (line,*, err=1000) tmpindex, qcp_atom(i)
			if((qcp_atom(i) .lt.1).or.(qcp_atom(i).gt.nqat)) then
				write(*,'(a,i4)') 'Invalid Q-atom number for QCP, i = ',qcp_atom(i)
				qatom_load_fep = .false.
			else if (i .gt. 1) then
                                ! loop downwards to see if there are double descriptions
                                do j = i - 1 , 1 ,-1
				if (qcp_atom(i) .eq. qcp_atom(j)) then
					write(*,'(a,i4)') 'Double definition of QCP atom, i = ',qcp_atom(i)
					qatom_load_fep = .false.
				end if
                                end do
			end if
! need to add write out part so we know the atoms actually assigned
		end do
	else 
! use previous definitions from MD input file
	select case (qcp_enum)
		case (QCP_ALLATOM)
! just use all atoms
			qcp_atnum = nqat
			allocate(qcp_atom(qcp_atnum))
			do i=1, nqat
				qcp_atom(i) = i
			end do
		case (QCP_HYDROGEN)
! use only atoms that can be identified as hydrogens in FEP file
! selection is mass
! first get number of atoms, then loop again to assign them
			qcp_atnum = 0
			do i=1, nqat
				if (.not.heavy(iqseq(i))) then
					qcp_atnum = qcp_atnum + 1
				end if
			end do
			if (qcp_atnum .gt. 0 ) then
! now allocate + assign :)
! need to loop again ot have tmp allocate ... not sure which one is better
				allocate(qcp_atom(qcp_atnum))
				qcp_atnum = 0
				do i=1, nqat
					if (.not.heavy(iqseq(i))) then
						qcp_atnum = qcp_atnum + 1
						qcp_atom(qcp_atnum) = i
					end if
				end do
			else
! whoops, no hydrogens ????
! turn of QCP and call the user an idiot
				use_QCP = .false.
				write(*,'(a)') 'QCP hydrogen setting did not result in any atoms being assigned! Did you try to be smart? QCP disabled!'
			end if
		case (QCP_FEPATOM)
! use tried to be smart and did not assign any QCP atoms in FEP file
! disable QCP and make fun of the user
			write(*,'(a)') 'No QCP atoms assigned in FEP file with explicit QCP assignment set! QCP is now turned off! I guess this was not intentional!'
		case default
! whoops memory must be trashed, because we don't know this value
! better kill program before something bad happens
			write(*,'(a)') '>>> ERROR: No such QCP setting! Program will terminate due to expected memory corruption!'
			qatom_load_fep = .false.
	end select
	end if ! qcp_select
        write(*,'(a)') 'Using the following atoms for QCP, in order of appearance'
        write(*,*) qcp_atom(1:qcp_atnum)
end if ! use qcp
! if qcp is still on and the user wanted mass perturbation, now it is time looking for this info in the fep file
        if(use_qcp.and.use_qcp_mass) then
        section='qcp_mass'
        tmp_qcp_num = prm_count(section)
! needs to be same size as qcp_atnum, and will assign masses in order of appearance
        allocate(qcp_mass(qcp_atnum))
        if (tmp_qcp_num .ne. qcp_atnum) then
                write(*,'(a)') 'WARNING: Better to define mass perturbation values for all atoms in QCP region. Filling from default mass values'
                do i = 1, qcp_atnum
! mass selection can be an issue here, we only take default masses from the first appearence of the atom type
                        qcp_mass(i) =  qmass(qiac(qcp_atom(i),1)) !  iaclib(iac(iqseq(qcp_atom(i))))%mass
                        end do  
        end if

        do i=1,tmp_qcp_num
        if(.not. prm_get_line(line)) goto 1000
                read (line,*, err=1000) tmpindex
                read (line,*, err=1000) tmpindex, qcp_mass(tmpindex)
                if((qcp_mass(tmpindex) .lt. zero)) then
                        write(*,'(a,i4)') '>>> ERROR: No negative mass allowed by physics for qatom ',tmpindex
                        write(*,'(a,f8.4)') '>>> ERROR: Mass is ',qcp_mass(tmpindex)
                        qatom_load_fep = .false.
                else
                        write(*,'(a,i4,a,f8.4)') 'Mass of qatom ',tmpindex,' set to ',qcp_mass(tmpindex)
                end if
        end do
        write(*,'(a)') 'Mass values used for QCP atoms in order of appearance'
        write(*,'(a)') 'Qatom Mass'
        do i = 1, qcp_atnum
        write(*,'(i4,f8.3)') qcp_atom(i),qcp_mass(i)
        end do
        end if
        call prm_close
	return

	!error handling code
1000	write(*,1900) i,section
	call prm_close
	qatom_load_fep = .false.
1900	format('>>>>> ERROR: Read error at line ',i2,' of section [',a,']')
  !.......................................................................
end function qatom_load_fep

!-------------------------------------------------------------------------

logical function bond_harmonic_in_any_state(k)
	integer, intent(in)			::	k
	integer						::	st

	bond_harmonic_in_any_state = .false.
	do st=1, nstates
		if(qbnd(k)%cod(st) /= 0) then
			if(qbondlib(qbnd(k)%cod(st))%fk /= 0.) then
				!the bond types is harmonic
				write(*,547) k, st
				bond_harmonic_in_any_state = .true.
			end if
		end if
	end do
547 format('>>>>> ERROR: Bond',i3,' is harmonic in state',i2)
end function bond_harmonic_in_any_state

end module QATOM
