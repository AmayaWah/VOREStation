/datum/admin_secret_item/admin_secret/show_crew_manifest
	name = "Show Crew Manifest"

/datum/admin_secret_item/admin_secret/show_crew_manifest/execute(var/mob/user)
	. = ..()
	if(!.)
		return
	var/dat
	dat += "<h4>Crew Manifest</h4>"
	dat += GLOB.data_core.get_manifest()

	var/datum/browser/popup = new(user, "manifest", "Manifest", 370, 420)
	popup.set_content(dat)
	popup.open()
