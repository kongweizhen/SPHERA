!----------------------------------------------------------------------------------------------------------------------------------
! SPHERA (Smoothed Particle Hydrodynamics research software; mesh-less Computational Fluid Dynamics code).
! Copyright 2005-2015 (RSE SpA -formerly ERSE SpA, formerly CESI RICERCA, formerly CESI-; SPHERA has been authored for RSE SpA by 
!    Andrea Amicarelli, Antonio Di Monaco, Sauro Manenti, Elia Bon, Daria Gatti, Giordano Agate, Stefano Falappi, 
!    Barbara Flamini, Roberto Guandalini, David Zuccalà).
! Main numerical developments of SPHERA: 
!    Amicarelli et al. (2015,CAF), Amicarelli et al. (2013,IJNME), Manenti et al. (2012,JHE), Di Monaco et al. (2011,EACFM). 
! Email contact: andrea.amicarelli@rse-web.it

! This file is part of SPHERA.
! SPHERA is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
! SPHERA is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
! GNU General Public License for more details.
! You should have received a copy of the GNU General Public License
! along with SPHERA. If not, see <http://www.gnu.org/licenses/>.
!----------------------------------------------------------------------------------------------------------------------------------

!----------------------------------------------------------------------------------------------------------------------------------
! Program unit: GeneratePart     
! Description: Particle positions (initial conditions).             
!----------------------------------------------------------------------------------------------------------------------------------
subroutine GeneratePart(IC_loop)
!------------------------
! Modules
!------------------------ 
use I_O_file_module
use Static_allocation_module
use Hybrid_allocation_module
use Dynamic_allocation_module
use I_O_diagnostic_module

!------------------------
! Declarations
!------------------------
!------------------------
! Explicit interfaces
!------------------------
implicit none
integer(4),intent(IN) :: IC_loop
integer(4) :: Nt,Nz,Mate,IsopraS,NumParticles,i,j,k,dimensioni,NumPartPrima    
integer(4) :: aux_factor,i_vertex,j_vertex,test_xy,test_z,n_levels,nag_aux
integer(4) :: i_face,j_node,npi,ier,test_face,test_dam,test_xy_2
double precision :: distance_hor,z_min,aux_scal,rnd,h_reservoir
double precision :: aux_vec(3)
integer(4),dimension(SPACEDIM) :: Npps
double precision,dimension(SPACEDIM) :: MinOfMin,XminReset
double precision,dimension(:),allocatable    :: z_aux
double precision,dimension(:,:),allocatable :: Xmin,Xmax
character(len=lencard)  :: nomsub = "GeneratePart"
type(TyParticle),dimension(:),allocatable    :: pg_aux
!------------------------
! Allocations
!------------------------
call random_seed()
test_z = 0
if (IC_loop==2) then
   do Nz=1,NPartZone
      if (Partz(Nz)%IC_source_type==2) test_z = 1
   end do 
endif
if (test_z==0) nag = 0 
NumParticles = 0
if (ncord == 2) then
   dimensioni = NumTratti
   else
      dimensioni = NumFacce
end if
allocate (xmin(spacedim,dimensioni),xmax(spacedim,dimensioni))
!------------------------
! Initializations
!------------------------
MinOfMin = max_positive_number
if (Domain%tipo=="bsph") then
! In case of DB-SPH boundary treatment, there is a fictitious fluid reservoir 
! top, which completes the kernel suppport (only for pre-processing)
   h_reservoir = Partz(Nz)%H_res + 3.d0 * Domain%h
   else
      h_reservoir = Partz(Nz)%H_res
endif
!------------------------
! Statements
!------------------------
! Loop over the zones in order to set the initial minimum and maximum 
! sub-zone coordinates
first_cycle: do Nz=1,NPartZone
! To search for the maximum and minimum "partzone" coordinates
   Partz(Nz)%coordMM(1:Spacedim,1) =  max_positive_number
   Partz(Nz)%coordMM(1:Spacedim,2) =  max_negative_number
! Loop over the different regions belonging to a same zone
   do Nt=Partz(Nz)%Indix(1),Partz(Nz)%Indix(2)
      Xmin(1:SPACEDIM,nt) =  max_positive_number
      Xmax(1:SPACEDIM,nt) =  max_negative_number
! To search for the minimum and maximum coordinates of the current zone 
! In 2D
      if (ncord==2) then
         call FindLine(Xmin,Xmax,Nt)
! To search for the minimum and maximum coordinates of the current subzone 
! in 3D
         else
         call FindFrame(Xmin,Xmax,Nt)
      end if
! To evaluate the minimum and maximum coordinates of the zone checking for 
! all the subzones
      do i=1,Spacedim
         if (Xmin(i,nt)<Partz(Nz)%coordMM(i,1)) Partz(Nz)%coordMM(i,1) =       &
                                                   Xmin(i,nt)
         if ( Xmax(i,nt) > Partz(Nz)%coordMM(i,2) ) Partz(Nz)%coordMM(i,2) =   &
                                                       Xmax(i,nt)
! To evaluate the minimum of subzones minimum coordinates
         MinOfMin(i) = min(MinOfMin(i),Xmin(i,nt))
      end do
   end do
end do first_cycle
! Loop over the zone in order to set the particle locations
second_cycle: do Nz=1,NPartZone
! To skip the boundaries not having types equal to "perimeter" or "pool"
   if ((Partz(Nz)%tipo/="peri").AND.(Partz(Nz)%tipo/="pool")) cycle second_cycle
! "perimeter" or "pool" conditions are set
   Mate = Partz(Nz)%Medium
   Partz(Nz)%limit(1) = NumParticles + 1
   if ((Partz(Nz)%tipo=="peri").and.(Partz(Nz)%IC_source_type==2)) then
! During the first IC loop
      if (IC_loop==1) then
! Update number of points/vertices of the zone
         Partz(Nz)%npoints = Partz(Nz)%ID_last_vertex -                        &
                             Partz(Nz)%ID_first_vertex + 1
         aux_factor = anint(Partz(Nz)%dx_CartTopog / Domain%dd) 
! Allocate the auxiliary arrays 
         allocate(z_aux(Partz(Nz)%npoints))
! Loops over Cartesian topography points
         z_min = max_positive_number
         do i_vertex=Partz(Nz)%ID_first_vertex,Partz(Nz)%ID_last_vertex
            z_min = min(z_min,(Vertice(3,i_vertex)))
         end do 
         nag_aux = Partz(Nz)%nag_aux
         allocate(pg_aux(nag_aux))
         NumParticles = NumParticles + 1
! Loops over Cartesian topography points
         do i_vertex=Partz(Nz)%ID_first_vertex,Partz(Nz)%ID_last_vertex
! Check if the vertex is inside the plan_reservoir     
            call point_inout_polygone(Vertice(1:2,i_vertex),                   &
               Partz(Nz)%plan_reservoir_points,                                &
               Partz(Nz)%plan_reservoir_pos(1,1:2),                            &
               Partz(Nz)%plan_reservoir_pos(2,1:2),                            &
               Partz(Nz)%plan_reservoir_pos(3,1:2),                            &
               Partz(Nz)%plan_reservoir_pos(4,1:2),test_xy)
            if (test_xy==1) then
! Set the minimum topography height among the closest 9 points
               z_aux(i_vertex) = max_positive_number 
               do j_vertex=1,Partz(Nz)%npoints
                  distance_hor = dsqrt((Vertice(1,i_vertex) -                  &
                                 Vertice(1,j_vertex)) ** 2 +                   &
                                 (Vertice(2,i_vertex) -                        &
                                 Vertice(2,j_vertex)) ** 2)
                  if (distance_hor<=(1.5*Partz(Nz)%dx_CartTopog))              &
                     z_aux(i_vertex) = min(z_aux(i_vertex),                    &
                                           (Vertice(3,j_vertex)))
               end do
! Generating daughter points of the Cartesian topography, according to dx
! (maybe the function "ceiling" would be better than "int" here)
               n_levels = int((h_reservoir - z_aux(i_vertex)) / Domain%dd) 
               do i=1,aux_factor
                  do j=1,aux_factor
                     do k=1,n_levels
! Setting coordinates                       
! We avoid particles to be located on the very diagonals of topography 
! (otherwise some particles could be not removed even if below the topography; 
! it is unclear why this rare eventuality would happen, 
! but no problem remains anymore)
                        pg_aux(NumParticles)%coord(1) = Vertice(1,i_vertex)    &
                                                        - aux_factor / 2.d0    &
                                                        * Domain%dd + (i -     &
                                                        1 + 0.501d0) *         &
                                                        Domain%dd
                        pg_aux(NumParticles)%coord(2) = Vertice(2,i_vertex)    &
                                                        - aux_factor / 2.d0    &
                                                        * Domain%dd + (j -     &
                                                        1 + 0.5d0) *           &
                                                        Domain%dd
                        pg_aux(NumParticles)%coord(3) = (h_reservoir -         &
                                                        Domain%dd / 2.d0) -    &
                                                        (k - 1) * Domain%dd
! Test if the particle is below the reservoir
! Loop over boundaries 
                        test_z = 0
                        test_face = 0
!$omp parallel do default(none)                                                &
!$omp shared(NumFacce,Tratto,BoundaryFace,Partz,Nz,pg_aux,test_face,test_z)    &
!$omp shared(NumParticles)                                                     &
!$omp private(i_face,aux_vec,aux_scal,test_xy)                         
                        do i_face=1,NumFacce
                           if (test_face==1) cycle
                           if (Tratto(BoundaryFace(i_face)%stretch)%zone==     &
                              Partz(Nz)%Car_top_zone) then  
! Test if the point lies inside the plan projection of the face     
                              call point_inout_polygone(                       &
                                 pg_aux(NumParticles)%coord(1:2),              &
                                 BoundaryFace(i_face)%nodes,                   &
                                 BoundaryFace(i_face)%Node(1)%GX(1:2),         &
                                 BoundaryFace(i_face)%Node(2)%GX(1:2),         &
                                 BoundaryFace(i_face)%Node(3)%GX(1:2),         &
                                 BoundaryFace(i_face)%Node(4)%GX(1:2),         &
                                 test_xy)
                              if (test_xy==1) then
! No need for a critical section to update test_face: only one face/process 
! is interested (no conflict); in particular cases there could be a conflict, 
! but no face has a preference and test_face cannot come back to zero 
! (no actual problem)
                                 test_face = 1
! Test if the point is invisible (test_z=1, below the topografy) or visible 
! (test_z=0) to the face 
                                 aux_vec(:) = pg_aux(NumParticles)%coord(:)    &
                                    - BoundaryFace(i_face)%Node(1)%GX(:)
                                 aux_scal = dot_product                        &
                                    (BoundaryFace(i_face)%T(:,3),aux_vec)
! No need for a critical section to update test_z: in particular cases there 
! could be a conflict, but the "if" condition would always provide the same 
! result
                                 if (aux_scal<=0.d0) test_z=1
                              endif
                           endif
                        enddo 
!$omp end parallel do 
! Check the presence of a dam zone
                        test_dam = 0
                        if (Partz(Nz)%dam_zone_ID>0) then
! Test if the point lies inside the plan projection of the dam zone
                           call point_inout_polygone(                          &
                              pg_aux(NumParticles)%coord(1:2),                 &
                              Partz(Nz)%dam_zone_n_vertices,                   &
                              Partz(Nz)%dam_zone_vertices(1,1:2),              &
                              Partz(Nz)%dam_zone_vertices(2,1:2),              &
                              Partz(Nz)%dam_zone_vertices(3,1:2),              &
                              Partz(Nz)%dam_zone_vertices(4,1:2),test_xy)
                           if (test_xy==1) then
                              test_face = 0
! Loop on the faces of the dam in the dam zone
!$omp parallel do default(none)                                                &
!$omp shared(NumFacce,test_dam,Tratto,BoundaryFace,Partz,Nz,pg_aux)            &
!$omp shared(NumParticles,test_face)                                           &
!$omp private(i_face,aux_vec,aux_scal,test_xy_2)
                              do i_face=1,NumFacce
                                 if (test_face==1) cycle
! Check if the face belongs to the dam_zone boundary and in particular to its 
! top                                  
if ((Tratto(BoundaryFace(i_face)%stretch)%zone==Partz(Nz)%dam_zone_ID).and.    &
                                       (BoundaryFace(i_face)%T(3,3)<0.)) then 
! Test if the particle horizontal coordinates ly inside the horizontal 
! projection of the face
                                    call point_inout_polygone(                 &
                                       pg_aux(NumParticles)%coord(1:2),        &
                                       BoundaryFace(i_face)%nodes,             &
                                       BoundaryFace(i_face)%Node(1)%GX(1:2),   &
                                       BoundaryFace(i_face)%Node(2)%GX(1:2),   &
                                       BoundaryFace(i_face)%Node(3)%GX(1:2),   &
                                       BoundaryFace(i_face)%Node(4)%GX(1:2),   &
                                       test_xy_2)
                                    if (test_xy_2==1) then
! Note: even if a particle simultanously belongs to 2 faces test_dam will 
! provide the same results: no matter the face order
!$omp critical (GeneratePart_cs)
                                       test_dam = 1  
                                       test_face = 1
! Test if the particle position is invisible (test_dam=1) or visible 
! (test_dam=0) to the dam. Visibility to the dam means invisibility to the 
! current dam top face. 
                                       aux_vec(:) =                           &
                                          pg_aux(NumParticles)%coord(:) -     &
                                          BoundaryFace(i_face)%Node(1)%GX(:)
                                       aux_scal = dot_product(                &
                                          BoundaryFace(i_face)%T(:,3),aux_vec)
                                       if (aux_scal<0.d0) then 
                                          test_dam=0
                                       endif
!$omp end critical (GeneratePart_cs)
                                    endif   
                                 endif
                              enddo
!$omp end parallel do                            
                           endif   
                        endif
! Update fluid particle counter
! Check if the fluid particle is visible both to the bottom reservoir and the 
! eventual dam
                        if ((test_z==0).and.(test_dam==0)) then
                           NumParticles = NumParticles + 1 
! Check the storage for the reached number of fluid particles
                           if (NumParticles>nag_aux) call diagnostic           &
                              (arg1=10,arg2=4,arg3=nomsub)  
                        endif
                     enddo
                  enddo
               enddo
            endif
         enddo 
! Allocate fluid particle array       
         NumParticles = NumParticles - 1
         PARTICLEBUFFER = NumParticles * Domain%COEFNMAXPARTI
         nag_reservoir_CartTopog = NumParticles
         allocate(pg(PARTICLEBUFFER),stat=ier)
         if (ier/=0) then
            write (nout,'(1x,a,i2)')                                           &
               "    Array PG not allocated. Error code: ",ier
            call diagnostic (arg1=4,arg3=nomsub)
            else
               write (nout,'(1x,a)') "    Array PG successfully allocated "
               pg(:) = PgZero
         end if
! Loop over the auxiliary particle array
!$omp parallel do default(none) shared(pg,pg_aux,NumParticles) private(npi)
         do npi=1,NumParticles
! Copy fluid particle array from the corresponding auxiliary array
            pg(npi) = pg_aux(npi)
         end do
!$omp end parallel do  
! Deallocate auxiliary arrays
         deallocate(z_aux)
         deallocate(pg_aux)
! Second IC loop
         else
! Loops over fluid particles 
!$omp parallel do default(none)                                                &
!$omp shared(nag_reservoir_CartTopog,Nz,Mate,Domain,pg)                        &
!$omp private(npi,rnd)  
            do npi=1,nag_reservoir_CartTopog
! to set particle parameters
               call SetParticleParameters(npi,Nz,Mate)   
! To modify random coordinates 
               if (Domain%RandomPos=='r') then
                  call random_number(rnd)
                  pg(npi)%coord(1) = pg(npi)%coord(1) + (2.d0 * rnd - 1.d0)    &
                                     * 0.1d0 * Domain%dd
                  call random_number(rnd)
                  pg(npi)%coord(2) = pg(npi)%coord(2) + (2.d0 * rnd - 1.d0)    &
                                     * 0.1d0 * Domain%dd
                  call random_number(rnd)
                  pg(npi)%coord(3) = pg(npi)%coord(3) + (2.d0 * rnd - 1.d0)    &
                                     * 0.1d0 * Domain%dd
               end if
            enddo
!$omp end parallel do  
            NumParticles = nag_reservoir_CartTopog
      endif
      else
! Loop over the different regions belonging to a same zone
         do Nt = Partz(Nz)%Indix(1), Partz(Nz)%Indix(2)
! To evaluate the number of particles for the subdomain Npps along all the 
! directions
            if ((Xmin(1,nt)== max_positive_number).or.                         &
                (Xmax(1,nt)== max_negative_number)) then
! The zone is declared but is not used
               Npps = -1
               else 
               do i=1,spacedim
                  NumPartPrima = Nint((Xmin(i,nt) - MinOfMin(i)) / Domain%dd)
                  Xminreset(i) = MinOfMIn(i) + NumPartPrima * Domain%dd
                  Npps(i) = NInt((Xmax(i,nt) - XminReset(i)) / Domain%dd)  
               end do
            end if
! To force almost one particle if the domain width in a direction is smaller  
! than dx
            if (ncord==2) where (Npps==0) Npps = 1
! To consider the "pool" condition: set "Isopra=1" if it crosses the 
! "virtual" side
            if (Partz(Nz)%tipo=="pool") then
               Xmax(Partz(Nz)%ipool,Nt) = Partz(Nz)%pool
               IsopraS = 1   
               else
                  IsopraS = 0
            end if     
! To set the particles in the zone
            Call SetParticles (Nt,Nz,Mate,XminReset,Npps,NumParticles,         &
                               IsopraS)
         end do
! To set the upper pointer for the particles in the nz-th zone
         Partz(Nz)%limit(2) = NumParticles
   endif
end do second_cycle
test_z = 0
if (IC_loop==2) then
   do Nz=1,NPartZone
      if (Partz(Nz)%IC_source_type==2) test_z = 1
   end do 
endif
if (test_z==0) nag = NumParticles
nagpg = nag
!------------------------
! Deallocations
!------------------------
deallocate (xmin,xmax)
return
end subroutine GeneratePart

