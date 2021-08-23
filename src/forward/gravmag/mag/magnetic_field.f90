! Custom TOMOFAST module for computation of total field.
! This module only computes the magnetic tensor which
! can be used to calculate the total field at any point
! outside the magnetizing volume.

module magnetic_field
    ! imports for compatability
    use global_typedefs
    use grid 
    
    implicit none 
    private

    ! degree to radian
    double precision, parameter :: d2rad = PI / 180.d0

    ! main
    type, public :: t_magnetic_field
        private

        ! external field intensity in nT
        double precision :: intensity

        ! allocate magnetic tensor
        !double precision, dimension(3) :: tx, ty, tz

        ! allocate magnetic field vectors
        double precision, dimension(3) :: magv, fv
    
    contains
        private

        procedure, public, pass     :: initialize => init_mag_field
        procedure, public, pass     :: magprism => magnetic_field_magprism

        procedure, private, nopass  :: sharmbox
        procedure, private, nopass  :: dircos

    end type t_magnetic_field

contains

!==============================================================================
! Initializes the magnetic field by calculating and storing their direction
! cosines.
! Currently the ambient magnetic field components are not used 
!==============================================================================
subroutine init_mag_field(self, mi, md, fi, fd, theta, intensity)
    ! intents
    class(t_magnetic_field), intent(inout) :: self
    double precision, intent(in) :: mi, md, fi, fd, theta, intensity

    ! local
    double precision :: ma, mb, mc
    double precision :: fa, fb, fc

    self%intensity = intensity
    call self%dircos(mi, md, theta, ma, mb, mc)
    call self%dircos(fi, fd, theta, fa, fb, fc) ! not used - left alone for compat

    self%magv = (/ ma, mb, mc /)
    self%fv =   (/ fa, fb, fc /) ! not used!

end subroutine init_mag_field

!==============================================================================
! note: dircos subroutine has not been modified
!
!  Subroutine DIRCOS computes direction cosines from inclination
!  and declination.
!
!  Input parameters:
!    incl:  inclination in degrees positive below horizontal.
!    decl:  declination in degrees positive east of true north.
!    azim:  azimuth of x axis in degrees positive east of north.
!
!  Output parameters:
!    a,b,c:  the three direction cosines.
!==============================================================================
subroutine dircos(incl, decl, azim, a, b, c)
    double precision, intent(in)    :: incl, decl, azim
    double precision, intent(out)   :: a, b, c
  
    double precision :: xincl, xdecl, xazim
  
    xincl = incl * d2rad
    xdecl = decl * d2rad
    xazim = azim * d2rad
  
    a = dcos(xincl) * dcos(xdecl - xazim)
    b = dcos(xincl) * dsin(xdecl - xazim)
    c = dsin(xincl)
  
end subroutine dircos

!==============================================================================
! Calculates the magnetic tensor for each point and is returned to the calling process
! This subroutine is meant to perform mbox on a set of voxels before returning their 
! respective magnetic tensor flattened in vector form.
! This is just a slightly modified version of the original magprism subroutine to 
! accomodate the new algorithm
!==============================================================================
subroutine magnetic_field_magprism(self, nelements, data_j, grid, Xdata, Ydata, Zdata, sensit_line)
    ! intent in
    class(t_magnetic_field), intent(in)     :: self
    !double precision                        :: magv(3), intensity
    integer, intent(in)                     :: nelements, data_j
    type(t_grid), intent(in)                :: grid
    real(kind=CUSTOM_REAL)                  :: Xdata(:), Ydata(:), Zdata(:)

    ! intent out
    real(kind=CUSTOM_REAL), intent(out)     :: sensit_line(:)

    ! local
    integer             :: i, j
    double precision    :: tx(3), ty(3), tz(3)
    double precision    :: mx, my, mz

    do i = 1,nelements
        tx = (/0.d0, 0.d0, 0.d0/)
        ty = (/0.d0, 0.d0, 0.d0/)
        tz = (/0.d0, 0.d0, 0.d0/)
        mx = 0.d0; my = 0.d0; mz = 0.d0

        call self%sharmbox(Xdata(data_j), Ydata(data_j), Zdata(data_j), &
                        grid%X1(i), grid%Y1(i), grid%Z1(i),         &
                        grid%X2(i), grid%Y2(i), grid%Z2(i),         &
                        tx, ty, tz)
                        
    ! could be probably more efficient using fortran's native matrix multiplication support
        do j = 1,3
            mx = mx + tx(j) * self%intensity * self%magv(j)! * mag_susc
            my = my + ty(j) * self%intensity * self%magv(j)! * mag_susc
            mz = mz + tz(j) * self%intensity * self%magv(j)! * mag_susc
        end do

        sensit_line(i) = (mx * self%magv(1) + my * self%magv(2) + mz * self%magv(3)) / (4.d0 * PI)

    end do
end subroutine magnetic_field_magprism

!===================================================================================
! Rewritten MBOX to use the algorithm proposed by P. Vallabh Sharma in his 1966 paper
! [Rapid Computation of Magnetic Anomalies and Demagnetization Effects Caused by Arbitrary Shape]
! Requires the DIRCOS subroutine.
!
! units:
!   coordinates:        m
!   field intensity:    nT
!   incl/decl/azi:      deg
!   mag suscept.:       cgs
!
! inputs:
!   x0, y0, z0      coordinates of the observation point
!   x1, y1, z1      coordinates of one of the corners on the top face, where z1 is the depth
!   x2, y2, z2      coordinates of the opposite corner on the bottom face, where z2 is the depth
! 
! outputs:
!   tx = [txx txy txz]
!   ty = [tyx tyy tyz]
!   tz = [tzx tzy tzz]
!   components of the magnetic tensor
!===================================================================================
subroutine sharmbox(x0,y0,z0, x1,y1,z1, x2,y2,z2, ts_x,ts_y,ts_z)
    ! intent in
    !class(t_magnetic_field), intent(in)     :: self
    double precision, intent(in)            :: x0,y0,z0, x1,y1,z1, x2,y2,z2

    ! intent out
    double precision, intent(out)           :: ts_x(3), ts_y(3), ts_z(3)

    ! local
    double precision :: rx1, rx2,        ry1, ry2,        rz1, rz2
    double precision :: rx1sq, rx2sq,    ry1sq, ry2sq,    rz1sq, rz2sq
    double precision :: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8
    double precision :: R1, R2, R3, R4
    double precision :: dx, dy, dz, eps = 1.d-8
    logical          :: l_inside 
    
    l_inside = .false.

    ! relative coordinates to obs
    ! voxel runs from x1 to x2, y1 to y2, z1 to z2
    ! observation points at obs_x obs_y obs_z
    rx1 = x1 - x0 + eps; ! rx1 = -u2
    rx2 = x2 - x0 + eps; ! rx2 = -u1
    ry1 = y1 - y0 + eps; ! ry1 = -v2
    ry2 = y2 - y0 + eps; ! ry2 = -v1
    rz1 = z1 - z0 + eps; ! rz1 = -w2
    rz2 = z2 - z0 + eps; ! rz2 = -w1

    ! squares
    rx1sq = rx1 ** 2; rx2sq = rx2 ** 2;
    ry1sq = ry1 ** 2; ry2sq = ry2 ** 2;
    rz1sq = rz1 ** 2; rz2sq = rz2 ** 2;

    R1 = ry2sq + rx2sq ! -v1**2 + -u1**2 -> R1
    R2 = ry2sq + rx1sq ! -v1**2 + -u2**2 -> R3
    R3 = ry1sq + rx2sq ! -v2**2 + -u1**2 -> R2
    R4 = ry1sq + rx1sq ! -v2**2 + -u2**2 -> R4
    arg1 = SQRT(rz2sq + R2)
    arg2 = SQRT(rz2sq + R1)
    arg3 = SQRT(rz1sq + R1)
    arg4 = SQRT(rz1sq + R2)
    arg5 = SQRT(rz2sq + R3)
    arg6 = SQRT(rz2sq + R4)
    arg7 = SQRT(rz1sq + R4)
    arg8 = SQRT(rz1sq + R3)

    ! ts_xx
    ts_x(1) =   DATAN2(ry1 * rz2, (rx2 * arg5 + eps)) - &
                DATAN2(ry2 * rz2, (rx2 * arg2 + eps)) + &
                DATAN2(ry2 * rz1, (rx2 * arg3 + eps)) - &
                DATAN2(ry1 * rz1, (rx2 * arg8 + eps)) + & 
                DATAN2(ry2 * rz2, (rx1 * arg1 + eps)) - &
                DATAN2(ry1 * rz2, (rx1 * arg6 + eps)) + &
                DATAN2(ry1 * rz1, (rx1 * arg7 + eps)) - &
                DATAN2(ry2 * rz1, (rx1 * arg4 + eps))

    ! ts_yx
    ts_y(1) =   DLOG((rz2 + arg2 + eps) / (rz1 + arg3 + eps)) - &
                DLOG((rz2 + arg1 + eps) / (rz1 + arg4 + eps)) + &
                DLOG((rz2 + arg6 + eps) / (rz1 + arg7 + eps)) - &
                DLOG((rz2 + arg5 + eps) / (rz1 + arg8 + eps))

    ! ts_yy
    ts_y(2) =   DATAN2(rx1 * rz2, (ry2 * arg1 + eps)) - &
                DATAN2(rx2 * rz2, (ry2 * arg2 + eps)) + &
                DATAN2(rx2 * rz1, (ry2 * arg3 + eps)) - &
                DATAN2(rx1 * rz1, (ry2 * arg4 + eps)) + &
                DATAN2(rx2 * rz2, (ry1 * arg5 + eps)) - &
                DATAN2(rx1 * rz2, (ry1 * arg6 + eps)) + &
                DATAN2(rx1 * rz1, (ry1 * arg7 + eps)) - &
                DATAN2(rx2 * rz1, (ry1 * arg8 + eps))

    ! following computations do not reuse variables so it may be
    ! faster to just compute them on the fly instead of storing
    ! them. It does help legibility, however
    R1 = ry2sq + rz1sq
    R2 = ry2sq + rz2sq
    R3 = ry1sq + rz1sq
    R4 = ry1sq + rz2sq
    arg1 = SQRT(rx1sq + R1)
    arg2 = SQRT(rx2sq + R1)
    arg3 = SQRT(rx1sq + R2)
    arg4 = SQRT(rx2sq + R2)
    arg5 = SQRT(rx1sq + R3)
    arg6 = SQRT(rx2sq + R3)
    arg7 = SQRT(rx1sq + R4)
    arg8 = SQRT(rx2sq + R4)

    ! ts_yz
    ts_y(3) =   DLOG((rx1 + arg1 + eps) / (rx2 + arg2 + eps)) - &
                DLOG((rx1 + arg3 + eps) / (rx2 + arg4 + eps)) + &
                DLOG((rx1 + arg7 + eps) / (rx2 + arg8 + eps)) - &
                DLOG((rx1 + arg5 + eps) / (rx2 + arg6 + eps))

    R1 = rx2sq + rz1sq
    R2 = rx2sq + rz2sq
    R3 = rx1sq + rz1sq
    R4 = rx1sq + rz2sq
    arg1 = SQRT(ry1sq + R1)
    arg2 = SQRT(ry2sq + R1)
    arg3 = SQRT(ry1sq + R2)
    arg4 = SQRT(ry2sq + R2)
    arg5 = SQRT(ry1sq + R3)
    arg6 = SQRT(ry2sq + R3)
    arg7 = SQRT(ry1sq + R4)
    arg8 = SQRT(ry2sq + R4)

    ! ts_xz
    ts_x(3) =   DLOG((ry1 + arg1 + eps) / (ry2 + arg2 + eps)) - &
                DLOG((ry1 + arg3 + eps) / (ry2 + arg4 + eps)) + &
                DLOG((ry1 + arg7 + eps) / (ry2 + arg8 + eps)) - &
                DLOG((ry1 + arg5 + eps) / (ry2 + arg6 + eps))

    ! checking if point is inside the voxel
    ! if so, use poisson's relation
    dx = x2 - x1 
    dy = y2 - y1 
    dz = z2 - z1
    ! this check doesnt work for some reason
    !if (dz + rz1 > 0.d0 .and. -rz1 > 0.d0) then 
    !    if (dx + rx1 > 0.d0 .and. -rx1 > 0.d0) then 
    !        if (dy + ry1 > 0.d0 .and. -ry1 > 0.d0) then 
    !            inside = .true.
    !        end if
    !    end if
    !end if

	!if ((x0 < x1 .and. x0 > x2) .or. (x0 > x1 .and. x0 < x2)) then
	!	if ((y0 < y1 .and. y0 > y2) .or. (y0 > y1 .and. y0 < y2)) then
	!		if ((z0 < z1 .and. z0 > z2) .or. (z0 > z1 .and. z0 < z2)) then
	!			inside = .true.
	!		end if
	!	end if
	!end if
	
	if (x0 > min(x1,x2) .and. x0 < max(x1,x2)) then
		if (y0 > min(y1,y2) .and. y0 < max(y1,y2)) then
			if (-z0 > min(-z1,-z2) .and. -z0 < max(-z1,-z2)) then
				l_inside = .true.
			end if
		end if
	end if
	

    ! filling the rest of the tensor
    ! ts_zz
    if (l_inside) then
    	print *, "Observation point inside target voxel!"
    	print *, "obs:", x0,y0,z0
    	print *, "voxel:", x1,x2, y1,y2, z1,z2
    	
        ts_z(3) = -1 * (ts_x(1) + ts_y(2) + 4*PI) ! poisson
    else
        ts_z(3) = -1 * (ts_x(1) + ts_y(2)) ! gauss
    end if

    ! ts_zy
    ts_z(2) = ts_y(3)

    ! ts_xy
    ts_x(2) = ts_y(1)

    ! ts_zx
    ts_z(1) = ts_x(3)

end subroutine sharmbox

end module magnetic_field
