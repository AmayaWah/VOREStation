#define BLOOD_MINIMUM_STOP_PROCESS 2.1 // Define to avoid hitting 0 blood.
/****************************************************
				BLOOD SYSTEM
****************************************************/
//Blood levels. These are percentages based on the species blood_volume var.
//Retained for archival/reference purposes - KK
/*
var/const/BLOOD_VOLUME_SAFE =    85
var/const/BLOOD_VOLUME_OKAY =    75
var/const/BLOOD_VOLUME_BAD =     60
var/const/BLOOD_VOLUME_SURVIVE = 40
*/
var/const/CE_STABLE_THRESHOLD = 0.5

/mob/living/carbon/human/var/datum/reagents/vessel // Container for blood and BLOOD ONLY. Do not transfer other chems here.
/mob/living/carbon/human/var/var/pale = 0          // Should affect how mob sprite is drawn, but currently doesn't.

/***Initializes blood vessels
 * Called code/modules/mob/living/carbon/human/human.dm#L1259 set_species procedure with 0 args
 * Also called by inject_blood as fallback with amt = injected_amount
 * MUST be followed by calling fixblood() allways.
***/
/mob/living/carbon/human/proc/make_blood(var/amt = 0)

	if(vessel)
		return

	if(species.flags & NO_BLOOD)
		return

	vessel = new/datum/reagents(species.blood_volume)
	vessel.my_atom = src

	if(!should_have_organ(O_HEART)) //We want the var for safety but we can do without the actual blood.
		return

	if(!amt)
		vessel.add_reagent(REAGENT_ID_BLOOD,species.blood_volume)
	else
		vessel.add_reagent(REAGENT_ID_BLOOD, clamp(amt, 1, species.blood_volume))


//Resets blood data
/mob/living/carbon/human/proc/fixblood()
	for(var/datum/reagent/blood/B in vessel.reagent_list)
		if(B.id == REAGENT_ID_BLOOD)
			B.data = list(	"donor"=src,"viruses"=null,"species"=species.name,"blood_DNA"=dna.unique_enzymes,"blood_colour"= species.get_blood_colour(src),"blood_type"=dna.b_type,	\
							"resistances"=null,"trace_chem"=null, "virus2" = null, REAGENT_ID_ANTIBODIES = list(), "blood_name" = species.get_blood_name(src))

			if(isSynthetic())
				B.data["species"] = "synthetic"

			B.color = B.data["blood_colour"]
			B.name = B.data["blood_name"]

// Takes care blood loss and regeneration
/mob/living/carbon/human/handle_blood()
	if(inStasisNow())
		return

	if(!should_have_organ(O_HEART))
		return

	if(stat != DEAD && bodytemperature >= 170)	//Dead or cryosleep people do not pump the blood.

		var/blood_volume_raw = vessel.get_reagent_amount(REAGENT_ID_BLOOD)
		var/blood_volume = round((blood_volume_raw/species.blood_volume)*100) // Percentage.

		//Blood regeneration if there is some space
		if(blood_volume_raw < species.blood_volume)
			var/datum/reagent/blood/B = locate() in vessel.reagent_list //Grab some blood
			if(B) // Make sure there's some blood at all
				if(B.data["donor"] != src) //If it's not theirs, then we look for theirs
					for(var/datum/reagent/blood/D in vessel.reagent_list)
						if(D.data["donor"] == src)
							B = D
							break

				B.volume += 0.1 // regenerate blood VERY slowly
				if(CE_BLOODRESTORE in chem_effects)
					B.volume += chem_effects[CE_BLOODRESTORE]

		// Damaged heart virtually reduces the blood volume, as the blood isn't
		// being pumped properly anymore.
		if(species && should_have_organ(O_HEART))
			var/obj/item/organ/internal/heart/heart = internal_organs_by_name[O_HEART]

			if(has_modifier_of_type(/datum/modifier/bloodpump))
				blood_volume_raw *= 1
				blood_volume *= 1
			else if(!heart)
				blood_volume_raw = 0
				blood_volume = 0
			else if(heart.is_broken())
				blood_volume_raw *= 0.3
				blood_volume *= 0.3
			else if(heart.is_bruised())
				blood_volume_raw *= 0.7
				blood_volume *= 0.7
			else if(heart.damage)
				blood_volume_raw *= 0.8
				blood_volume *= 0.8

		//Effects of bloodloss
		var/dmg_coef = 1				//Lower means less damage taken
		var/threshold_coef = 1			//Lower means the damage caps off lower

		if(CE_STABLE in chem_effects)
			dmg_coef = 0.5
			threshold_coef = 0.75
//	These are Bay bits, do some sort of calculation.
//			dmg_coef = min(1, 10/chem_effects[CE_STABLE]) //TODO: add effect for increased damage
//			threshold_coef = min(dmg_coef / CE_STABLE_THRESHOLD, 1)

		if(blood_volume_raw >= species.blood_volume*species.blood_level_safe)
			if(pale)
				pale = 0
				update_icons_body()
		else if(blood_volume_raw >= species.blood_volume*species.blood_level_warning)
			if(!pale)
				pale = 1
				update_icons_body()
				var/word = pick("dizzy","woozy","faint","disoriented","unsteady")
				to_chat(src, span_red("You feel slightly [word]"))
			if(prob(1))
				var/word = pick("dizzy","woozy","faint","disoriented","unsteady")
				to_chat(src, span_red("You feel [word]"))
			if(getOxyLoss() < 20 * threshold_coef)
				adjustOxyLoss(3 * dmg_coef)
		else if(blood_volume_raw >= species.blood_volume*species.blood_level_danger)
			if(!pale)
				pale = 1
				update_icons_body()
			eye_blurry = max(eye_blurry,6)
			if(getOxyLoss() < 50 * threshold_coef)
				adjustOxyLoss(10 * dmg_coef)
			adjustOxyLoss(1 * dmg_coef)
			if(prob(15))
				Paralyse(rand(1,3))
				var/word = pick("dizzy","woozy","faint","disoriented","unsteady")
				to_chat(src, span_red("You feel dangerously [word]"))
		else if(blood_volume_raw >= species.blood_volume*species.blood_level_fatal)
			adjustOxyLoss(5 * dmg_coef)
//			adjustToxLoss(3 * dmg_coef)
			if(prob(15))
				var/word = pick("dizzy","woozy","faint","disoriented","unsteady")
				to_chat(src, span_red("You feel extremely [word]"))
		else //Not enough blood to survive (usually)
			if(!pale)
				pale = 1
				update_icons_body()
			eye_blurry = max(eye_blurry,6)
			Paralyse(3)
			adjustToxLoss(3 * dmg_coef)
			adjustOxyLoss(75 * dmg_coef) // 15 more than dexp fixes (also more than dex+dexp+tricord)

		// Without enough blood you slowly go hungry.
		if(blood_volume_raw < species.blood_volume*species.blood_level_safe)
			if(nutrition >= 300)
				adjust_nutrition(-10)
			else if(nutrition >= 200)
				adjust_nutrition(-3)

		//Bleeding out
		var/blood_max = 0
		var/blood_loss_divisor = 30.01	//lower factor = more blood loss

		// Some species bleed out differently
		blood_loss_divisor /= species.bloodloss_rate

		// Some modifiers can make bleeding better or worse.  Higher multiplers = more bleeding.
		var/blood_loss_modifier_multiplier = 1.0
		for(var/datum/modifier/M in modifiers)
			if(!isnull(M.bleeding_rate_percent))
				blood_loss_modifier_multiplier += (M.bleeding_rate_percent - 1.0)

		blood_loss_divisor /= blood_loss_modifier_multiplier


		//This 30 is the "baseline" of a cut in the "vital" regions (head and torso).
		for(var/obj/item/organ/external/temp in bad_external_organs)

			///First, we make sure it's not robotic.
			if(temp.robotic >= ORGAN_ROBOT)
				continue

			///Second, we process internal bleeding.
			for(var/datum/wound/internal_bleeding/W in temp.wounds)
				blood_loss_divisor = blood_loss_divisor+10 //IB is slower bloodloss than normal.
				var/bicardose = reagents.get_reagent_amount(REAGENT_ID_BICARIDINE)
				var/inaprovaline = reagents.get_reagent_amount(REAGENT_ID_INAPROVALINE)
				var/myeldose = reagents.get_reagent_amount(REAGENT_ID_MYELAMINE)
				if(!(W.can_autoheal() || (bicardose && inaprovaline) || myeldose))	//bicaridine and inaprovaline stop internal wounds from growing bigger with time, unless it is so small that it is already healing
					W.open_wound(0.1)
				if(prob(1))
					custom_pain("You feel a stabbing pain in your [name]!", 50)
				if(CE_STABLE in chem_effects)
					blood_loss_divisor = max(blood_loss_divisor + 30, 1) //Inaprovaline is great on internal wounds.
				if(temp.applied_pressure) //Putting pressure on the afflicted wound helps stop the arterial bleeding.
					if(ishuman(temp.applied_pressure))
						var/mob/living/carbon/human/H = temp.applied_pressure
						H.bloody_hands(src, 0)
						blood_loss_divisor += 30 //If you're putting pressure on that limb due to there being an external bleed there, you apply some pressure to the internal bleed as well.
				remove_blood(W.damage/blood_loss_divisor) //line should possibly be moved to handle_blood, so all the bleeding stuff is in one place. //Hi. 2025 here. Just did that. ~Diana

			///Thirdly, we check to see if the limb is bleeding EXTERNALLY
			if(!(temp.status & ORGAN_BLEEDING))
				continue
			///Finally, we process external wounds.
			for(var/datum/wound/W in temp.wounds)
				if(W.bleeding())
					if(W.damage_type == PIERCE) //gunshots and spear stabs bleed more
						blood_loss_divisor = max(blood_loss_divisor - 5, 1)
					else if(W.damage_type == BRUISE) //bruises bleed less
						blood_loss_divisor = max(blood_loss_divisor + 5, 1)
					//the farther you get from those vital regions, the less you bleed
					//depending on how dangerous bleeding turns out to be, it might be better to only apply the reduction to hands and feet
					if((temp.organ_tag == BP_L_ARM) || (temp.organ_tag == BP_R_ARM) || (temp.organ_tag == BP_L_LEG) || (temp.organ_tag == BP_R_LEG))
						blood_loss_divisor = max(blood_loss_divisor + 5, 1)
					else if((temp.organ_tag == BP_L_HAND) || (temp.organ_tag == BP_R_HAND) || (temp.organ_tag == BP_L_FOOT) || (temp.organ_tag == BP_R_FOOT))
						blood_loss_divisor = max(blood_loss_divisor + 10, 1)
					if(CE_STABLE in chem_effects)	//Inaprov slows bloodloss
						blood_loss_divisor = max(blood_loss_divisor + 10, 1)
					if(temp.applied_pressure)
						if(ishuman(temp.applied_pressure))
							var/mob/living/carbon/human/H = temp.applied_pressure
							H.bloody_hands(src, 0)
						//somehow you can apply pressure to every wound on the organ at the same time
						//you're basically forced to do nothing at all, so let's make it pretty effective
						var/min_eff_damage = max(0, W.damage - 10) / (blood_loss_divisor / 5) //still want a little bit to drip out, for effect
						blood_max += max(min_eff_damage, W.damage - 30) / blood_loss_divisor
					else
						blood_max += W.damage / blood_loss_divisor

			if(temp.open)
				blood_max += 2 //Yer stomach is cut open
		drip(blood_max)

//Makes a blood drop, leaking amt units of blood from the mob
/mob/living/carbon/human/proc/drip(var/amt)
	if(remove_blood(amt))
		blood_splatter(src,src)

/mob/living/carbon/human/proc/remove_blood(var/amt)
	if(!should_have_organ(O_HEART)) //TODO: Make drips come from the reagents instead.
		return 0

	if(!amt)
		return 0

	var/current_blood = vessel.get_reagent_amount(REAGENT_ID_BLOOD)
	if(current_blood < BLOOD_MINIMUM_STOP_PROCESS)
		return 0 //We stop processing under 3 units of blood because apparently weird shit can make it overflowrandomly.

	if(amt > current_blood)
		amt = current_blood - 2	// Bit of a safety net; it's impossible to add blood if there's not blood already in the vessel.

	return vessel.remove_reagent(REAGENT_ID_BLOOD,amt)

/****************************************************
				BLOOD TRANSFERS
****************************************************/

//Gets blood from mob to the container, preserving all data in it.
/mob/living/carbon/proc/take_blood(obj/item/reagent_containers/container, var/amount)

	var/datum/reagent/B = get_blood(container.reagents)
	if(!B)
		B = new /datum/reagent/blood
	B.holder = container
	B.volume += amount

	//set reagent data
	B.data["donor"] = src
	if(!B.data["viruses"])
		B.data["viruses"] = list()

	for(var/datum/disease/D in GetSpreadableViruses())
		B.data["viruses"] |= D.Copy()

	for(var/datum/disease/D in GetDormantDiseases())
		B.data["viruses"] |= D.Copy()

	if(!B.data["resistances"])
		B.data["resistances"] = list()

	if(B.data["resistances"])
		B.data["resistances"] |= GetResistances()
	B.data["blood_DNA"] = copytext(src.dna.unique_enzymes,1,0)
	B.data["blood_type"] = copytext(src.dna.b_type,1,0)

	// Putting this here due to return shenanigans.
	if(ishuman(src))
		var/mob/living/carbon/human/H = src
		B.data["blood_colour"] = H.species.get_blood_colour(H)
		B.color = B.data["blood_colour"]

	var/list/temp_chem = list()
	for(var/datum/reagent/R in src.reagents.reagent_list)
		temp_chem += R.id
		temp_chem[R.id] = R.volume
	B.data["trace_chem"] = list2params(temp_chem)
	return B

//For humans, blood does not appear from blue, it comes from vessels.
/mob/living/carbon/human/take_blood(obj/item/reagent_containers/container, var/amount)

	if(!should_have_organ(O_HEART))
		return null

	if(vessel.get_reagent_amount(REAGENT_ID_BLOOD) < max(amount, BLOOD_MINIMUM_STOP_PROCESS))
		return null

	. = ..()
	remove_blood(amount) // Removes blood if human

//Transfers blood from container ot vessels
/mob/living/carbon/proc/inject_blood(var/datum/reagent/blood/injected, var/amount)
	if (!injected || !istype(injected))
		return
	var/list/sniffles = injected.data["viruses"]
	for(var/ID in sniffles)
		var/datum/disease/D = ID
		if(D.spread_flags & (DISEASE_SPREAD_SPECIAL | DISEASE_SPREAD_NON_CONTAGIOUS)) // You can't put non-contagius diseases in blood, but just in case
			continue
		ContractDisease(D)
	if (injected.data["resistances"] && prob(5))
		antibodies |= injected.data["resistances"]
	if (injected.data[REAGENT_ID_ANTIBODIES] && prob(5))
		antibodies |= injected.data[REAGENT_ID_ANTIBODIES]
	var/list/chems = list()
	chems = params2list(injected.data["trace_chem"])
	for(var/C in chems)
		src.reagents.add_reagent(C, (text2num(chems[C]) / species.blood_volume) * amount)//adds trace chemicals to owner's blood
	reagents.update_total()

//Transfers blood from reagents to vessel, respecting blood types compatability.
/mob/living/carbon/human/inject_blood(var/datum/reagent/blood/injected, var/amount)

	if(!should_have_organ(O_HEART))
		reagents.add_reagent(REAGENT_ID_BLOOD, amount, injected.data)
		reagents.update_total()
		return

	var/datum/reagent/blood/our = get_blood(vessel)

	if (!injected)
		return
	if(!our)
		log_debug("[src] has no blood reagent, proceeding with fallback reinitialization.")
		var/vessel_old = vessel
		vessel = null
		qdel(vessel_old)
		make_blood(amount)
		if(!vessel)
			log_debug("Failed to re-initialize blood datums on [src]!")
			return
		if(vessel.total_volume < species.blood_volume)
			vessel.add_reagent(REAGENT_ID_BLOOD, species.blood_volume - vessel.total_volume)
		else if(vessel.total_volume > species.blood_volume)
			vessel.maximum_volume = species.blood_volume
		fixblood()
		our = get_blood(vessel)
		if(!our)
			log_debug("Failed to re-initialize blood datums on [src]!")
			return


	if(blood_incompatible(injected.data["blood_type"],our.data["blood_type"],injected.data["species"],our.data["species"]) )
		reagents.add_reagent(REAGENT_ID_TOXIN,amount * 0.5)
		reagents.update_total()
	else
		vessel.add_reagent(REAGENT_ID_BLOOD, amount, injected.data)
		vessel.update_total()
	..()

//Gets human's own blood.
/mob/living/carbon/proc/get_blood(datum/reagents/container)
	var/datum/reagent/blood/res = locate() in container.reagent_list //Grab some blood
	if(res) // Make sure there's some blood at all
		if(res.data["donor"] != src) //If it's not theirs, then we look for theirs
			for(var/datum/reagent/blood/D in container.reagent_list)
				if(D.data["donor"] == src)
					return D
	return res

/proc/blood_incompatible(donor,receiver,donor_species,receiver_species)
	if(!donor || !receiver) return 0

	if(donor_species && receiver_species)
		if(donor_species != receiver_species)
			return 1

	var/donor_antigen = copytext(donor,1,length(donor))
	var/receiver_antigen = copytext(receiver,1,length(receiver))
	var/donor_rh = (findtext(donor,"+")>0)
	var/receiver_rh = (findtext(receiver,"+")>0)

	if(donor_rh && !receiver_rh) return 1
	switch(receiver_antigen)
		if("A")
			if(donor_antigen != "A" && donor_antigen != "O") return 1
		if("B")
			if(donor_antigen != "B" && donor_antigen != "O") return 1
		if("O")
			if(donor_antigen != "O") return 1
		//AB is a universal receiver.
	return 0

/proc/blood_splatter(var/target,var/datum/reagent/blood/source,var/large)

	//Vorestation Edit Start - We're not going to splatter at all because we're in something and that's silly.
	if(istype(source,/atom/movable))
		var/atom/movable/A = source
		if(!isturf(A.loc))
			return
	//VOREStation Edit End
	var/obj/effect/decal/cleanable/blood/B
	var/decal_type = /obj/effect/decal/cleanable/blood/splatter
	var/turf/T = get_turf(target)
	var/synth = 0

	if(ishuman(source))
		var/mob/living/carbon/human/M = source
		if(M.isSynthetic()) synth = 1
		source = M.get_blood(M.vessel)

	//Someone fed us a weird source. Let's log it.
	if(source && !istype(source, /datum/reagent/blood))
		log_debug("A blood splatter was made using non-blood datum [source]!")
		source = null //Clear the source since it's invalid. Fallback to non-source behavior.

	// Are we dripping or splattering?
	var/list/drips = list()
	// Only a certain number of drips (or one large splatter) can be on a given turf.
	for(var/obj/effect/decal/cleanable/blood/drip/drop in T)
		drips |= drop.drips
		qdel(drop)
	if(!large && drips.len < 3)
		decal_type = /obj/effect/decal/cleanable/blood/drip

	// Find a blood decal or create a new one.
	B = locate(decal_type) in T
	if(!B)
		B = new decal_type(T)

	var/obj/effect/decal/cleanable/blood/drip/drop = B
	if(istype(drop) && drips && drips.len && !large)
		drop.add_overlay(drips)
		drop.drips |= drips

	// If there's no data to copy, call it quits here.
	if(!istype(source))
		return B

	// Update appearance.
	if(source.data["blood_colour"])
		B.basecolor = source.data["blood_colour"]
		B.synthblood = synth
		B.update_icon()

	if(source.data["blood_name"])
		B.name = source.data["blood_name"]

	// Update blood information.
	if(source.data["blood_DNA"])
		var/list/new_data = list()
		if(source.data["blood_type"])
			new_data[source.data["blood_DNA"]] = source.data["blood_type"]
		else
			new_data[source.data["blood_DNA"]] = "O+"
		B.init_forensic_data().merge_blooddna(null,new_data)

	// Update virus information.
	if(source.data["viruses"])
		B.viruses = source.data["viruses"]

	B.fluorescent  = 0
	B.invisibility = INVISIBILITY_NONE
	return B

#undef BLOOD_MINIMUM_STOP_PROCESS
