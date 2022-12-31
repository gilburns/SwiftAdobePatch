#!/bin/bash

####################################################
#  SwiftAdobePatch
####################################################
#
# This script is meant to be used with Jamf Pro and makes use of swiftDialog.
# https://github.com/bartreardon/swiftDialog
#
# swiftDialog is required. This script will fail without it installed. 
# Minimum OS support for swiftDialog is Big Sur (11.x)
#
# The idea behind this script is that it alerts the user that there are required Adobe
# updates that need to be installed. The script will allow end users to postpone/defer
# updates X amount of times. If the script is postponed the maximun number of times,
# then the user has no choice, but to save work and quit the apps that need patching
# or the script will force quit the apps and continue patching.
#
# This script should work rather reliably going back to 11.x, but at this point
# the real testing has only been done on 12.x.
#
#
# JAMF Pro Script Parameters:
# Parameter 4: Optional. Number of postponements allowed. Default: 7
# Parameter 5: Optional. Number of seconds dialog should remain up. Default: 600 seconds
# Parameter 6: Optional. Contact email, number, or department name used in messaging.
#              Default: IT
# Parameter 7: Optional. Set your own custom icon. Default is Adobe CC Desktop icon.
#
#
####################################################
# Here is the expected workflow with this script:
####################################################
#
# If no apps need to be updated, the script will simply exit.
#
# If no user is logged in, or the apps that need to be updated are not running,
#    the script will install updates in the background.
#
# If a user is logged in and there are updates that require apps be quit, the user
#    will get prompted to update or to postpone.
#
# If the user has reached the maximum number of deferrals, then they are instead 
#    notified that patching is mandatory. They must save work and quit the apps, 
#    or if they don't apps, the apps are forced to quit and patching will occur.
#
####################################################

echo ""
echo "Starting Adobe Update Process"

##########################
# Record the start time  #
# to calculate total     #
# time later             #
##########################
EPOCH_START_TIME=`/bin/date "+%s"`

echo "   $(date -r ${EPOCH_START_TIME})"
echo "-----------------------------------"

##########################
##     Declarations     ##
##########################

TestingMode="No"
UpdateResults=0

##########################
##     Version Info     ##
##########################
ScriptVersion="2.1"

##########################
##   Script arguments   ##
##########################

# DeferralValue is the number of times the script run can be deferred.
DeferralValue="${4}"
# TimeOutinSec is the number of seconds the script will wait for user response.
TimeOutinSec="${5}"
# ITContact is used for the display of the IT info in the process dialogs
ITContact="${6}"
# AdobeIcon is the path to a graphic file that can be used for the dialogs
AdobeIcon="${7}"

# Set default values. If nothing is supplied, the script will use these defaults
[[ -z "${DeferralValue}" ]] && DeferralValue=7
[[ -z "${TimeOutinSec}" ]] && TimeOutinSec=600
[[ -z "${ITContact}" ]] && ITContact="IT"

# If non-existent path has been supplied for ${7}, then set an alternate icon
if [[ ! -e "${AdobeIcon}" ]]; then
	AdobeIcon1="/Applications/Utilities/Adobe Creative Cloud/ACC/Creative Cloud.app/Contents/Resources/CreativeCloudApp.icns"
	AdobeIcon2="/Applications/Utilities/Adobe Creative Cloud/Utils/Creative Cloud Installer.app/Contents/Resources/CreativeCloudInstaller.icns"
	AdobeIcon3="/Applications/Utilities/Adobe Creative Cloud/Utils/Creative Cloud Uninstaller.app/Contents/Resources/CreativeCloudInstaller.icns"
	
	if [ -f "${AdobeIcon1}" ]; then
		AdobeIcon="${AdobeIcon1}"
    elif [ -f "${AdobeIcon2}" ]; then
		AdobeIcon="${AdobeIcon2}"
    elif [ -f "${AdobeIcon3}" ]; then
		AdobeIcon="${AdobeIcon3}"
	fi
fi

##########################
# Set path where deferral#
# plist will be placed   #
##########################
DeferralPlistPath="/Library/Application Support/JAMF"
[[ ! -d "${DeferralPlistPath}" ]] && /bin/mkdir -p "${DeferralPlistPath}"

DeferralPlist="${DeferralPlistPath}/com.custom.deferrals.plist"
BundleID="com.adobe.RemoteUpdateManager"

CurrentDeferralValue="$(/usr/libexec/PlistBuddy -c "print :"${BundleID}":count" "${DeferralPlist}" 2>/dev/null)"

# echo "${CurrentDeferralValue}"
# echo "${BundleID}"
# echo "${DeferralPlist}"
# CurrentDeferralValue=0


####################################################
##              Language Strings                  ##
####################################################
##########################
#      EN - English      #
##########################
EN_TitlePrompt="${ITContact} - Adobe Software Update"
		
EN_StandardUpdatePrompt="#### Adobe updates available...
				
If you are unable to update at this time, you may choose to postpone for one day.


###### *Remaining Postponements: ${CurrentDeferralValue}*
   

Please quit the following Adobe applications:"

EN_ForcedUpdatePrompt="#### There are Adobe updates for your Mac that are required.
You have already postponed updates the maximum number of times.

Please save your work, quit apps and then click '**Update**'. Otherwise, when the counter gets to zero, this message will disappear and the following Adobe applications will be forced to quit.
		  
		
##### *Updates will proceed automatically at the end of the countdown, even if you do not take action*.
"

EN_ContactMsg="#### Error installing Adobe updates. 
		
- Did you leave an Adobe app running that needed to be quit?
		
  
  		
		
We will try applying updates again tomorrow. If the error persists, please contact ${ITContact}.
"
	
# Message shown when running background updates
EN_HUDMessage="#### Adobe software updates are being installed in the background. 

Do not turn off this computer during this time.

This message will go away when updates are complete.

If you feel too much time has passed, please contact ${ITContact}.
  

  

###### START TIME: "

EN_ForceQuit="Forcing all Adobe apps that require patching to exit."

EN_UpdateSuccessful="update was successful"
EN_UpdateFailed="update failed"
EN_ExitCode="Exit code"
EN_StartingUpdate="Starting Update Process."
EN_Updating="Updating"
EN_RunningSkipping="is running. Skipping."
EN_WaitingForQuit="Waiting for app to quit"
EN_CleanUp="Updates completed. Cleaning up."
# Buttons
EN_Continue="Waiting to Continue"
EN_Postpone="Postpone"
EN_OK="OK"
EN_Update="Update"
EN_Working="Working"
EN_Killing="Force quitting"

##########################
#      ES - Spanish      #
##########################
ES_TitlePrompt="${ITContact} - Actualización de software de Adobe"

ES_StandardUpdatePrompt="#### Actualizaciones de Adobe disponibles...
				
Si no puede actualizar en este momento, puede optar por posponer por un día.


###### *Aplazamientos restantes: ${CurrentDeferralValue}*
   

Salga de las siguientes aplicaciones de Adobe:"

ES_ForcedUpdatePrompt="#### Hay actualizaciones de Adobe para su Mac que son necesarias.
Ya has pospuesto actualizaciones la cantidad máxima de veces.

Guarde su trabajo, cierre las aplicaciones y luego haga clic en '**Actualizar**'. De lo contrario, cuando el contador llegue a cero, este mensaje desaparecerá y las siguientes aplicaciones de Adobe se verán obligadas a cerrarse..
		  
		
##### *Las actualizaciones se realizarán automáticamente al final de la cuenta regresiva, incluso si no realiza ninguna acción.*.
"
		
ES_ContactMsg="#### Error al instalar las actualizaciones de Adobe. 
		
- ¿Dejaste en ejecución una aplicación de Adobe que debías cerrar?
		
Vamos a tratar de aplicar las actualizaciones de nuevo mañana. Si el error persiste, póngase en contacto con ${ITContact}.
"
	
# Message shown when running background updates
ES_HUDMessage="#### Las actualizaciones de software de Adobe se están instalando en segundo plano. 
		
No apague esta computadora durante este tiempo.

Este mensaje desaparecerá cuando se completen las actualizaciones y cerrarlo no detendrá el proceso de actualización..

Si siente que ha pasado demasiado tiempo, comuníquese con el departamento de ${ITContact}.
"
ES_ForceQuit="Forcing all Adobe apps that require patching to exit."

ES_UpdateSuccessful="la actualización fue exitosa"
ES_UpdateFailed="actualización fallida"
ES_ExitCode="código de salida"
ES_StartingUpdate="Inicio del proceso de actualización."
ES_Updating="Actualizando"
ES_RunningSkipping="se está ejecutando. Salto a la comba."
ES_WaitingForQuit="Esperando a que la aplicación se cierre"
ES_CleanUp="Actualizaciones completadas. Limpiar."
# Buttons
ES_Continue="Continuar"
ES_Postpone="Posponer"
ES_OK="OK"
ES_Update="Actualizar"
ES_Working="Laboral"
ES_Killing="Forzar el cierre de"

##########################
#      FR - French       #
##########################
FR_TitlePrompt="${ITContact} - Adobe Mise à jour logicielle"

FR_StandardUpdatePrompt="#### Mises à jour Adobe disponibles...
				
Si vous ne parvenez pas à mettre à jour pour le moment, vous pouvez choisir de reporter d'un jour.


###### *Reports restants: ${CurrentDeferralValue}*
   

Veuillez quitter les applications Adobe suivantes:"

FR_ForcedUpdatePrompt="#### Des mises à jour Adobe sont nécessaires pour votre Mac.
Vous avez déjà reporté les mises à jour le nombre maximum de fois.

Veuillez enregistrer votre travail, quittez les applications, puis cliquez sur '** Mettre à jour **'. Sinon lorsque le compteur arrivera à zéro, ce message disparaîtra et les applications Adobe suivantes seront forcées de se fermer.
		  
		
##### *Les mises à jour se poursuivront automatiquement à la fin du compte à rebours, même si vous n'agissez pas*.
"		
FR_ContactMsg="#### Erreur lors de l'installation des mises à jour Adobe. 
		
- Avez-vous laissé une application Adobe cours d'exécution qui devait être cesser de fumer?
		
Nous essaierons à nouveau d'appliquer les mises à jour demain. Si l'erreur persiste, veuillez contacter ${ITContact}.
"
	
# Message shown when running background updates
FR_HUDMessage="#### mises à jour logicielles Adobe sont en cours d'installation en arrière-plan. 
		
N'éteignez pas cet ordinateur pendant ce temps.

Ce message disparaîtra lorsque les mises à jour seront terminées et la fermeture n'arrêtera pas le processus de mise à jour.

Si vous vous sentez trop de temps a passé, s'il vous plaît contacter ${ITContact}.
"
FR_ForceQuit="Forcing all Adobe apps that require patching to exit."

FR_UpdateSuccessful="la mise à jour a réussi"
FR_UpdateFailed="mise à jour a échoué"
FR_ExitCode="Code de sortie"
FR_StartingUpdate="Démarrage du processus de mise à jour."
FR_Updating="Mise à jour"
FR_RunningSkipping="est en cours d'exécution. Saut."
FR_WaitingForQuit="En attente de la fermeture de l'application"
FR_CleanUp="Mises à jour terminées. Nettoyer."
# Buttons
FR_Continue="Continuer"
FR_Postpone="Retarder"
FR_OK="d'accord"
FR_Update="Mettre à jour"
FR_Working="Travail"
FR_Killing="Forcer à quitter"

##########################
## Verbiage For Messages #
##########################
lastUser=`defaults read /Library/Preferences/com.apple.loginwindow lastUserName`
checkLang=`su - ${lastUser} -c "defaults read -g AppleLocale"`

case ${checkLang} in
	fr_FR | fr_CA)
		# French
		
		# Dialogs
		TitlePrompt="${FR_TitlePrompt}"
		StandardUpdatePrompt="${FR_StandardUpdatePrompt}"
		ForcedUpdatePrompt="${FR_ForcedUpdatePrompt}"
		ContactMsg="${FR_ContactMsg}"
		HUDMessage="${FR_HUDMessage}"
		ForceQuit="${FR_ForceQuit}"

		UpdateSuccessful="${FR_UpdateSuccessful}"
		UpdateFailed="${FR_UpdateFailed}"
		ExitCode="${FR_ExitCode}"
		StartingUpdate="${FR_StartingUpdate}"
		Updating="${FR_Updating}"
		RunningSkipping="${FR_RunningSkipping}"
		WaitingForQuit="${FR_WaitingForQuit}"
		CleanUp="${FR_CleanUp}"
		# Buttons		
		Continue="${FR_Continue}"
		Postpone="${FR_Postpone}"
		OK="${FR_OK}"
		Update="${FR_Update}"
		Working="${FR_Working}"
		Killing="${FR_Killing}"
		;;
	es_ES | ca_ES | es_AR)
		# Spanish

		# Dialogs
		TitlePrompt="${ES_TitlePrompt}"
		StandardUpdatePrompt="${ES_StandardUpdatePrompt}"
		ForcedUpdatePrompt="${ES_ForcedUpdatePrompt}"
		ContactMsg="${ES_ContactMsg}"
		HUDMessage="${ES_HUDMessage}"
		ForceQuit="${ES_ForceQuit}"

		UpdateSuccessful="${ES_UpdateSuccessful}"
		UpdateFailed="${ES_UpdateFailed}"
		ExitCode="${ES_ExitCode}"
		StartingUpdate="${ES_StartingUpdate}"
		Updating="${ES_Updating}"
		RunningSkipping="${ES_RunningSkipping}"
		WaitingForQuit="${ES_WaitingForQuit}"
		CleanUp="${ES_CleanUp}"
		# Buttons		
		Continue="${ES_Continue}"
		Postpone="${ES_Postpone}"
		OK="${ES_OK}"
		Update="${ES_Update}"
		Working="${ES_Working}"
		Killing="${ES_Killing}"
		;;
	*)
		# Default
		# English

		# Dialogs
		TitlePrompt="${EN_TitlePrompt}"
		StandardUpdatePrompt="${EN_StandardUpdatePrompt}"
		ForcedUpdatePrompt="${EN_ForcedUpdatePrompt}"
		ContactMsg="${EN_ContactMsg}"
		HUDMessage="${EN_HUDMessage}"
		ForceQuit="${EN_ForceQuit}"

		UpdateSuccessful="${EN_UpdateSuccessful}"
		UpdateFailed="${EN_UpdateFailed}"
		ExitCode="${EN_ExitCode}"
		StartingUpdate="${EN_StartingUpdate}"
		Updating="${EN_Updating}"
		RunningSkipping="${EN_RunningSkipping}"
		WaitingForQuit="${EN_WaitingForQuit}"
		CleanUp="${EN_CleanUp}"
		# Buttons		
		Continue="${EN_Continue}"
		Postpone="${EN_Postpone}"
		OK="${EN_OK}"
		Update="${EN_Update}"
		Working="${EN_Working}"
		Killing="${EN_Killing}"
		;;
esac

##########################
## End Language Strings ##
##########################

##########################
# RUM documentation:
# https://helpx.adobe.com/enterprise/admin-guide.html/enterprise/using/using-remote-update-manager.ug.html
##########################
RUM="/usr/local/bin/RemoteUpdateManager"

##########################
# Adobe Product Versions
# https://helpx.adobe.com/enterprise/kb/apps-deployed-without-base-versions.html
##########################
AdobeProductVersions=("AEFT,After Effects" "ACR,Camera Raw" "APRO,Acrobat" "RDR,Reader" "FLPR,Animate" "AUDT,Audition" "KBRG,Bridge" "CHAR,Character Animator" "ESHR,Dimension" "DRWV,Dreamweaver" "FRSC,Fresco" "ILST,Illustrator" "AICY,InCopy" "IDSN,InDesign" "LRCC,Lightroom" "LTRM,Lightroom Classic" "MUSE,Muse" "AME,Media Encoder" "PHSP,Photoshop" "PRLD,Prelude" "PPRO,Premiere Pro" "RUSH,Premiere Rush" "SBSTD,Substance Designer" "SBSTP,Substance Painter" "SBSTA,Substance Sampler" "STGR,Substance Stager" "SPRK,XD" "CCXP,CCX Process" "COCM,STI_ColorCommonSet_CMYK" "COPS,STI_Color_Photoshop" "CORE,STI_Color_HD" "CORG,STI_ColorCommonSet_RGB" "COSY,CoreSync" "KASU,HD_ASU" "LIBS,CC Library")

AdobeProductVersionsArraylength=${#AdobeProductVersions[@]}

##########################
# Adobe Channel IDs
# https://helpx.adobe.com/il_en/enterprise/kb/remote-update-manager-channel-ids.html
##########################
AdobeChannelIdVersions=("AdobeAcrobatXIPro-11.0, Acrobat" "AdobeAfterEffectsCS6-11,After Effects" "AdobeAfterEffects-12.0.0,After Effects" "AdobeAfterEffects-13.0.0-Trial,After Effects" "AdobeAfterEffects-13.5.0-Trial,After Effects" "AdobeAuditionCS6-5.0,Audition" "AdobeAuditionCC-6.0,Audition" "AdobeAudition-7.0.0-Trial,Audition" "AdobeAudition-8.0.0-Trial,Audition" "AdobeCaptivate7-7.0,Captivate" "AdobeCaptivate8-8.0,Captivate" "AdobeInCopyCS6-8.0,InCopy" "AdobeInCopyCC-9.0,InCopy" "AdobeInCopyCC2014-10.0,InCopy" "AdobeInCopyCC2015-11.0,InCopy" "AdobeMediaEncoder-8.0.0-Trial,Media Encoder" "AdobeMediaEncoder-9.0.0-Trial,Media Encoder" "AdobePresenterVideoExpress10-10.0,Presenter")

AdobeChannelIdVersionsArraylength=${#AdobeChannelIdVersions[@]}

declare -a AdobePatchArray=()
declare -a AdobeRunArray=()
declare -a DialogListArray=()

AdobePatchArrayLength=0
AdobeRunArrayLength=0
DialogListArrayLength=0

# Path to temporarily store list of available software updates.
ListOfAdobeUpdates="/var/tmp/ListOfAdobeUpdates"

##########################
# Binaries
##########################
swiftDialogApp="/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/Dialog"
dialogApp="/usr/local/bin/dialog"
dialogLog="/var/tmp/dialog.log"
jamf="/usr/local/bin/jamf"

# Check for dark mode? Change dialogs?
# checkMode=$(su - ${lastUser} -c "defaults read -g AppleInterfaceStyle" 2>/dev/null) 


##########################
##       Functions      ##
##########################

setDeferral (){
    # Notes: PlistBuddy "print" will print stderr to stdout when file is not found.
    #   File Doesn't Exist, Will Create: /path/to/file.plist
    BundleID="${1}"
    DeferralType="${2}"
    DeferralValue="${3}"
    DeferralPlist="${4}"
    
DeferralCount="$(/usr/libexec/PlistBuddy -c "print :"${BundleID}":count" "${DeferralPlist}" 2>/dev/null)"

# Set deferral count
if [[ -n "${DeferralCount}" ]] && [[ ! "${DeferralCount}" == *"File Doesn't Exist"* ]]; then
	/usr/libexec/PlistBuddy -c "set :"${BundleID}":count ${DeferralValue}" "${DeferralPlist}" 2>/dev/null
    else
    /usr/libexec/PlistBuddy -c "add :"${BundleID}":count integer ${DeferralValue}" "${DeferralPlist}" 2>/dev/null
fi
}

#
# Install all software updates
#
updateCLISilent (){
	if [[ "${TestingMode}" == "Yes" ]];then
		echo "** Just testing... Apps will NOT be patched **"
		SU_EC=0
	else
	
	    UpdateResults=0

		AdobePatchArrayLength=${#AdobePatchArray[@]}
		for (( i=0; i<${AdobePatchArrayLength}; i++ ));
		do
			CurrentProduct="${AdobePatchArray[$i]}"
			ProcessName=$(processFromPID "${CurrentProduct}")

			echo "Updating ${CurrentProduct} - ${ProcessName}"
		    SU_EC="$(updateCLISingle ${CurrentProduct})"
							
		    UpdateResults=$((${UpdateResults} + ${SU_EC}))
					
			if [[ ${SU_EC} -eq 0 ]]; then
				echo "   RemoteUpdateManager was successful. Exit Code: ${SU_EC}"
			else
				echo "   RemoteUpdateManager failed. Exit Code: ${SU_EC}"
        		echo "   Postpone remaining: ${CurrentDeferralValue}"
			fi    

		done
	
	fi
	
}


#
# Install updates for specified productVersion
#
updateCLISingle (){
    CurrentProduct=${1}
    
	if [[ "${TestingMode}" != "Yes" ]];then	
			"${RUM}" --action=install --productVersions="${CurrentProduct}" 1>> "${ListOfAdobeUpdates}" 2>> "${ListOfAdobeUpdates}" &		

		## Get the Process ID of the last command run in the background ($!)
		SUPID=$(echo "$!")

		## Wait for it to complete (wait)
		wait ${SUPID}

		SU_EC=$?
		
		echo ${SU_EC}
	else
		echo 0
	fi
}

#
# Install updates for all products
#
updateCLIAll (){
    
	if [[ "${TestingMode}" != "Yes" ]];then	

		"${RUM}" --action=install 1>> "${ListOfAdobeUpdates}" 2>> "${ListOfAdobeUpdates}" &

		## Get the Process ID of the last command run in the background ($!)
		SUPID=$(echo "$!")

		## Wait for it to complete (wait)
		wait ${SUPID}

		SU_EC=$?
		
		echo ${SU_EC}
	else
		echo 0
	fi
}

#
# Update through the GUI
#
updateGUI (){
    /bin/launchctl ${LMethod} ${LoggedInUserID} /usr/bin/open "/Applications/Utilities/Adobe Creative Cloud/ACC/Creative Cloud.app"
}

processFromPID (){
    # Returns the process name from an Adobe PID
    PIDToCheck="${1}"
        
    for (( i=0; i<${AdobeProductVersionsArraylength}; i++ ));
	do
		PID=$(echo "${AdobeProductVersions[$i]}" | cut -d, -f1)
		PName=$(echo "${AdobeProductVersions[$i]}" | cut -d, -f2)
		
		if [[ "${PIDToCheck}" == "${PID}" ]];then
			ProcessName="${PName}"
		fi
	done

	echo "${ProcessName}"
}

forceQuitRunningApps (){

		"${dialogApp}" --title "${TitlePrompt}" \
		--titlefont size=24 \
		--icon "${AdobeIcon}" \
		--message "${ForceQuit}" \
		--messagefont "size=16" \
		--button1text "${Working}…" \
		--button1disabled \
		--progress \
		--progresstext "${StartingUpdate}" \
		--progress \
		--height 200 \
		--iconsize 128 \
		--alignment left \
		--ontop \
		&

	# Force quit running Adobe apps that would be blocking the update process.
	echo "Force quit running Adobe apps"

	AdobeRunArrayLength=${#AdobeRunArray[@]}

	for (( i=0; i<${AdobeRunArrayLength}; i++ ));
	do
		echo "   Killing Adobe ${AdobeRunArray[$i]}"
		dialog_command "progresstext: ${Killing} Adobe ${AdobeRunArray[$i]}"
		/usr/bin/pkill -SIGKILL -f "${AdobeRunArray[$i]}" &>/dev/null
		sleep 3
	done

	sleep 2
	dialog_command "progresstext:     "
	sleep 2
	dialog_command "quit: "

}

#
# Check list of Adobe items for running apps
#
checkForRunningProcessesThatNeedPatching (){

	AdobeRunArray=()

	AdobePatchArrayLength=${#AdobePatchArray[@]}
	for (( i=0; i<${AdobePatchArrayLength}; i++ ));
	do
		# Check to see if it is running.
		CurrentProduct=$(processFromPID "${AdobePatchArray[$i]}")
# 		echo "${CurrentProduct}"
		runningCheck=$( pgrep "${CurrentProduct}" )
		
		if [ ! -z "${runningCheck}" ];then
# 			echo "Adobe ${CurrentProduct} is running"
			AdobeRunArray+=("${CurrentProduct}")
		fi
	done

	AdobeRunArrayLength=${#AdobeRunArray[@]}

# 	echo "AdobeRunArray: ${AdobeRunArray[@]}"
# 	echo "AdobeRunArrayLength: ${AdobeRunArrayLength}"

}

#
# Create the list to display in the swiftDialog prompt
#
createListForRunningProducts(){
# 	dialog_command "list: index: 0: delete:"
	dialog_command "list: clear"
	
# 	echo "AdobeRunArray: ${AdobeRunArray[@]}"
# 	echo "AdobeRunArrayLength: ${AdobeRunArrayLength}"

	for (( i=0; i<${AdobeRunArrayLength}; i++ ));
	do
		CurrentItem="${AdobeRunArray[$i]}"
		
		DialogListArray+=("${CurrentItem}")

		itemPID=$(pgrep "${CurrentItem}")

		# tail is needed in case there are multiple versons of a title running
		itemPath=$(ps -o comm= -p ${itemPID} | tail -1)
		
		# remove path levels x3 to get to the .app level
		itemPath="$(dirname "${itemPath}")"
		itemPath="$(dirname "${itemPath}")"
		itemPath="$(dirname "${itemPath}")"
		
		itemFilename=$(basename -- "${itemPath}")

		# Check that the item ends in .app to insure we got the right item
		itemExtension="${itemFilename##*.}"
		
		if [ "${itemExtension}" == "app" ];then
			# add app item to the dialog list
			dialog_command "listitem: add, title: ${CurrentItem}, icon: ${itemPath}, statustext: ${WaitingForQuit}"
		else
			# add item with generic Adobe icon to the dialog list
			dialog_command "listitem: add, title: ${CurrentItem}, icon: ${AdobeIcon}, statustext: ${WaitingForQuit}"
		fi		
	done
	
	DialogListArrayLength=${#DialogListArray[@]}

	if [ ${DialogListArrayLength} -gt 0 ];then
		dialog_command "list: show"
	fi

}

#
# Check to see if the list changed, if so, then update the swiftDialog
#
updateListForRunningProducts(){
	if [ "${#AdobeRunArray[@]}" -eq "${#DialogListArray[@]}" ]; then
		return
	else
		DialogListArray=()
		createListForRunningProducts
	fi
}

#
# Check a process by name to see if it is running
#
processRunCheck (){
    # Returns the process run status from name
	ProcessToCheck="${1}"
	RunCheck=0
	
	runningCheck=$( pgrep "Adobe ${ProcessToCheck}" )
	if [ ! -z "${runningCheck}" ];then
		# echo "Adobe ${PName} is running"
		RunCheck=1
	fi

	return ${RunCheck}
}

#
# Run the updates with swiftDialog GUI 
#
runUpdates (){
		"${dialogApp}" --title "${TitlePrompt}" \
		--titlefont size=24 \
		--icon "${AdobeIcon}" \
		--message "${HUDMessage} *$(/bin/date +"%b %d %Y %T")*" \
		--messagefont "size=16" \
		--button1text "${Working}…" \
		--button1disabled \
		--progress \
		--progresstext "${StartingUpdate}" \
		--height 325 \
		--iconsize 128 \
		--alignment left \
		--ontop \
		--moveable \
		&
    
    ## Run the Adobe updates    
#     echo "${AdobePatchArray[@]}"
    
    UpdateResults=0
    # AdobePatchArray
	echo "-----------------------------------"
	
    AdobePatchArrayLength=${#AdobePatchArray[@]}
	for (( i=0; i<${AdobePatchArrayLength}; i++ ));
	do
		CurrentProduct="${AdobePatchArray[$i]}"
		ProcessName=$(processFromPID "${CurrentProduct}")

		echo "Updating ${CurrentProduct} - ${ProcessName}"
		dialog_command "progresstext: ${Updating} Adobe ${ProcessName}"
		
		# Check to see if it is running.
		ProcessName=$(processFromPID "${CurrentProduct}")
		runningCheck=$( pgrep "${ProcessName}" )
		
		if [ ! -z "${runningCheck}" ];then
			echo "   Adobe ${ProcessName} is running. Skipping."	
			dialog_command "progresstext: Adobe ${ProcessName} ${RunningSkipping}"
			sleep 5
			SU_EC=3
		else
			echo "   Adobe ${ProcessName} not running. OK to update."	
			SU_EC="$(updateCLISingle ${CurrentProduct})"
		fi
	    
	    UpdateResults=$((${UpdateResults} + ${SU_EC}))

	    if [[ ${SU_EC} -eq 0 ]]; then
    		echo "   RemoteUpdateManager was successful"
			dialog_command "progresstext: Adobe ${ProcessName} ${UpdateSuccessful}"
   		else
        	echo "   RemoteUpdateManager failed. Exit Code: ${SU_EC}"
			dialog_command "progresstext: Adobe ${ProcessName} ${UpdateFailed}. ${ExitCode}: ${SU_EC}"
        	echo "   Postpone remaining: ${CurrentDeferralValue}"
			sleep 5
    	fi    
	done
 
	dialog_command "progresstext: ${CleanUp}"
	sleep 3
	dialog_command "progresstext: "
    ## Kill the Dialog.
	dialog_command "quit: "
	sleep 1
	
	echo "-----------------------------------"

    if [[ "${UpdateResults}" -eq 0 ]]; then
    	echo "   ${RUM} was successful for all"
    else
        echo "   ${RUM} had one or more failures."
        
		"${dialogApp}" --title "${TitlePrompt}" \
		--titlefont size=24 \
		--icon "${AdobeIcon}" --overlayicon warning \
		--message "${ContactMsg}" \
		--messagefont "size=16" \
		--button1text "${OK}" \
		--height 250 \
		--iconsize 128 \
		--quitoninfo \
		--alignment left \
		--ontop \
		--timer 20
			
		HELPER=$?

	fi

	# Have there been updates? Lets submit a new inventory.
	if [[ "${TestingMode}" != "Yes" ]];then
		echo "   Submitting JAMF inventory."
		"${jamf}" recon &>/dev/null
	fi
}

#
# Function to do best effort check if using presentation or web conferencing is active
#
checkForDisplaySleepAssertions(){
    Assertions="$(/usr/bin/pmset -g assertions | /usr/bin/awk '/NoDisplaySleepAssertion | PreventUserIdleDisplaySleep/ && match($0,/\(.+\)/) && ! /coreaudiod/ {gsub(/^\ +/,"",$0); print};')"
    
    # There are multiple types of power assertions an app can assert.
    # These specifically tend to be used when an app wants to try and prevent the OS from going to display sleep.
    # Scenarios where an app may not want to have the display going to sleep include, but are not limited to:
    #   Presentation (KeyNote, PowerPoint)
    #   Web conference software (Zoom, Webex)
    #   Screen sharing session
    # Apps have to make the assertion and therefore it's possible some apps may not get captured.
    # Some assertions can be found here: https://developer.apple.com/documentation/iokit/iopmlib_h/iopmassertiontypes
    if [[ "${Assertions}" ]]; then
        echo "The following display-related power assertions have been detected:"
        echo "${Assertions}"
        
        if grep -q "PreventUserIdleDisplaySleep named: \"Amphetamine" <<< ${Assertions}; then
        	echo "   We are ignoring this assertion."
			echo "-----------------------------------"
        elif grep -q "PreventUserIdleDisplaySleep named: \"Caffeine is running" <<< ${Assertions}; then
        	echo "   We are ignoring this assertion."        
			echo "-----------------------------------"
        elif grep -q "PreventUserIdleDisplaySleep named: \"Jolt of Caffeine is running" <<< ${Assertions}; then
        	echo "   We are ignoring this assertion."        
        else
			echo "Exiting script to avoid disrupting user while these power assertions are active."
	        updateRunCompleted
        	exit 0
        fi 
    fi
}

#
# Run completed, calculate the total time and report the results
#
updateRunCompleted(){
	EPOCH_STOP_TIME=`/bin/date "+%s"`
	EPOCH_DIFF=$(( ${EPOCH_STOP_TIME} - ${EPOCH_START_TIME} ))
	TIME_RESULT=`show_time ${EPOCH_DIFF}`
	echo "Time for run:  ${TIME_RESULT}"
}

#
# Check for Adobe updates YES/NO returned
#
updatesAvailable(){

	RUM_Details=$("${RUM}" --action=list > "${ListOfAdobeUpdates}" 2>&1)

	UpdateStatus=$(cat "${ListOfAdobeUpdates}" | grep -i "Following Updates are applicable\|Following Acrobat/Reader updates are applicable")

	if [ ! -z "${UpdateStatus}" ]; then
		updatesAvailable="YES"
	else
		updatesAvailable="NO"
	fi

	echo "${updatesAvailable}"
}

#
# Execute a swiftDialog command
#
dialog_command()
{
# 	echo $1
	echo $1  >> "${dialogLog}"
}

#
# Take a time in seconds and return a value in Days/Hours/Min/Secs
#
show_time()
{
	num=$1
	min=0
	hour=0
	day=0
	if((num>59));
	then
		((sec=num%60))
		((num=num/60))

		if((num>59));
		then
			((min=num%60))
			((num=num/60))

			if((num>23));
			then
				((hour=num%24))
				((day=num/24))
				echo "${day}"d "${hour}"h "${min}"m "${sec}"s
			else
				((hour=num))
				echo "${hour}"h "${min}"m "${sec}"s
			fi
		else
			((min=num))
			echo "${min}"m "${sec}"s
		fi
	else
		((sec=num))
		echo "${sec}"s
	fi
}

##########################
##    ACTUAL WORKING    ##
##     CODE  BELOW      ##
##########################


# Set up the deferral value if it does not exist already
if [[ -z "${CurrentDeferralValue}" ]] || [[ "${CurrentDeferralValue}" == *"File Doesn't Exist"* ]]; then
    setDeferral "${BundleID}" "${DeferralType}" "${DeferralValue}" "${DeferralPlist}"
    CurrentDeferralValue="$(/usr/libexec/PlistBuddy -c "print :"${BundleID}":count" "${DeferralPlist}" 2>/dev/null)"
fi


# Check that RUM is installed
if [ -f "${RUM}" ] ; then
	if [[ "${TestingMode}" == "Yes" ]];then	
	    RUM_Version=$( "${RUM}" --help 2>&1 | /usr/bin/awk ' NR==1{ print $5 } ' )
		echo "RemoteUpdateManager"
		echo "   Installed: ${RUM}"
		echo "   Version:   ${RUM_Version}"
		echo "-----------------------------------"
	fi
else
	echo "${RUM} not installed... exiting"
	echo "-----------------------------------"
	updateRunCompleted
	exit 1
fi

# Check that SwiftDialog App is installed
if [ -f "${swiftDialogApp}" ] ; then
	if [[ "${TestingMode}" == "Yes" ]];then	
		echo "SwiftDialog app"
		echo "   Installed: ${swiftDialogApp}"
		echo "-----------------------------------"
	fi
else
	echo "${swiftDialogApp} not installed... exiting"
	echo "-----------------------------------"
	updateRunCompleted
	exit 1
fi

# Check that SwiftDialog command line is installed
if [ -f "${dialogApp}" ] ; then
	if [[ "${TestingMode}" == "Yes" ]];then	
		echo "SwiftDialog command line"
		echo "   Installed: ${dialogApp}"
		echo "-----------------------------------"
	fi
else
	echo "${dialogApp} not installed... exiting"
	echo "-----------------------------------"
	updateRunCompleted
	exit 1
fi

# Perform basic test for updates
updateStatus=$(updatesAvailable)

# Capture full RUM details
RUM_Details=$( cat "${ListOfAdobeUpdates}" | tail -n +4 | sed -e '$ d' | awk '{$1="   "$1}1' )

echo "RUM Details at start:"
echo "${RUM_Details}"
echo "-----------------------------------"



# If no updates are indicated, then exit out now.
if [ "${updateStatus}" == "NO" ];then
	# Nothing to Update
	echo "Nothing to Update"
	
	if [[ "${TestingMode}" == "Yes" ]];then
		echo "Proceeding in testing mode"
	else
		setDeferral "${BundleID}" "${DeferralType}" "${DeferralValue}" "${DeferralPlist}"

		updateRunCompleted
#		uncomment for later
		exit 0
	fi
fi


#
# Basic check found that there was something to update.
# Build a detailed list of updates
#
if [[ "${TestingMode}" == "Yes" ]];then
	# Set values to fake things for the testing mode.
	AdobePatchArray=("APRO" "IDSN" "ILST" "PHSP")
# 	AdobePatchArray=("APRO")
else
	# Check all Adobe products individually
	#      See if they are installed
	#      See if they need an update
	#
	for (( i=0; i<${AdobeProductVersionsArraylength}; i++ ));
	do
		PID=$(echo "${AdobeProductVersions[$i]}" | cut -d, -f1)
		PName=$(echo "${AdobeProductVersions[$i]}" | cut -d, -f2)

		# Check to see if the app is installed on the machine.
		if [ "${PName}" == "Reader" ];then
			PName="Acrobat Reader"
		elif [ "${PName}" == "Acrobat"  ];then
			PName="Adobe Acrobat"		
		fi

		appInstalledTest=$(/usr/bin/mdfind "kMDItemKind == \"Application\" && kMDItemFSName == \"*$PName*\"c")

# 		echo "index: $i, ID: ${PID}, Name: ${PName}"
# 		echo "${appInstalledTest}"

		# If it is installed, check to see if it needs any updates.
		if [[ ! -z  "${appInstalledTest}" ]]; then
			#check for needed patches
			"${RUM}" --action=list --productVersions="${PID}" 2>&1 > "${ListOfAdobeUpdates}"
		
			UpdateStatus=$(grep -i "Following Updates are applicable\|Following Acrobat/Reader updates are applicable" "${ListOfAdobeUpdates}")
			if [ ! -z "${UpdateStatus}" ]; then
# 				echo ${UpdateStatus}
# 				echo "Needs update. Adding ${PID}" 
				AdobePatchArray+=("${PID}")
			fi
		fi
	done
fi


# Hopefully the detailed check found something to update?
# Check to see if we need to go any further.
if [[ ! ${AdobePatchArray[@]} ]]; then
	# No apps to update, could be other Adobe components?
	echo "Detailed check found nothing to update?"
	setDeferral "${BundleID}" "${DeferralType}" "${DeferralValue}" "${DeferralPlist}"

	# If we got here and the detailed list is empty, just run the full update.
	echo "Running full RUM update"
	SU_EC="$(updateCLIAll)"

	echo "   RemoteUpdateManager Full Run. Exit Code: ${SU_EC}"
	
	# Have there been updates? Lets submit a new inventory.
	if [[ "${TestingMode}" != "Yes" ]];then
		echo "   Submitting JAMF inventory."
		"${jamf}" recon &>/dev/null
	fi

	# Capture full RUM details afterwards

	# Perform basic test for updates to see if we got everything
	updateStatus=$(updatesAvailable)

	# Capture full RUM details
	RUM_Details=$( cat "${ListOfAdobeUpdates}" | tail -n +4 | sed -e '$ d' | awk '{$1="   "$1}1' )

	echo "-----------------------------------"
	echo "RUM Details at end:"
	echo "${RUM_Details}"
	echo "-----------------------------------"

	updateRunCompleted
	exit 0
else
	# Updates are available

	# check for running apps that require updates
	# Check if there are running Adobe apps to determine which dialog to display.
	checkForRunningProcessesThatNeedPatching
	
	echo "Updates available:"
	echo "   Updates: ${AdobePatchArray[@]}"	
	echo "   Running: ${AdobeRunArray[@]}"
	echo "-----------------------------------"
fi


# Determine currently logged in user
LoggedInUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }')"

# Determine logged in user's UID
LoggedInUserID=$(/usr/bin/id -u "${LoggedInUser}")
LMethod="asuser"


# If we get to this point, there are updates available.
# If there is no one logged in or no apps are running, let's try to run the updates.

if [[ "${LoggedInUser}" == "" ]] || [[ AdobeRunArrayLength -eq 0 ]]; then
	# Note why we went ahead with the silent update.
	if [[ "${LoggedInUser}" == "" ]];then
		echo "   No one logged in. Proceeding with updates"
	fi
	if [[ AdobeRunArrayLength -eq 0 ]];then
		echo "   No apps running. Proceeding with updates"
	fi
	
	echo "-----------------------------------"
    updateCLISilent
	echo "-----------------------------------"

    if [[ "${UpdateResults}" -eq 0 ]]; then
    	echo "   ${RUM} was successful for all"
    else
        echo "   ${RUM} had one or more failures."
        echo "   No user logged in, no contact dialog"
    fi

	# Have there been updates? Lets submit a new inventory.
	if [[ "${TestingMode}" != "Yes" ]];then
		echo "   Submitting JAMF inventory."
		"${jamf}" recon &>/dev/null
	fi
	
	RunUpdates_EC=${UpdateResults}
	
else
	
	# Check for Sleep Assertions that might indicate someone is presenting.
	# (We might not come back here. Exit possible in function)
    checkForDisplaySleepAssertions
    # If we came back, there were no sleep assertions preventing updates
    
    # Someone is logged in. Prompt if any updates require a restart ONLY IF the update timer has not reached zero
    
	# Someone is logged in. Lets check the deferral.
	if [[ "${CurrentDeferralValue}" -gt 0 ]]; then  # Deferrals are remaining.
		echo "Requesting update run from user."
		echo "    Current deferral = ${CurrentDeferralValue}"
		
		# Reduce the timer by 1. The script will run again the next day
		let CurrTimer=${CurrentDeferralValue}-1
		setDeferral "${BundleID}" "${DeferralType}" "${CurrTimer}" "${DeferralPlist}"
		
		# If someone is logged in and they have not canceled $DeferralValue times 
		# already prompt them to install updates and state how many more times they
		# can press 'Postpone' before updates run automatically.
		
		# Count the number of time we remind users to quit apps
		QuitTries=0
		Action="Patch"
		
		# Reset SECONDS so we can track the time on the dialog
		SECONDS=0
		
		# calculate dialog height
		dialogHeight=$((48 * ${AdobeRunArrayLength} + 256))

		"${dialogApp}" --title "${TitlePrompt}" \
			--titlefont size=24 \
			--icon "${AdobeIcon}" --overlayicon warning \
			--message "${StandardUpdatePrompt}" \
			--messagefont "size=16" \
			--infobuttontext "${Postpone}" \
			--button1text "${Continue}" \
			--button1disabled \
			--height ${dialogHeight} \
			--hidetimerbar \
			--iconsize 128 \
			--quitoninfo \
			--quitkey x \
			--listitem "Loading list" \
			--alignment left \
			--ontop \
			&

		checkForRunningProcessesThatNeedPatching
		createListForRunningProducts

		while [[ ${AdobeRunArrayLength} -gt 0 ]]
		do
			dialogRunningCheck=$( pgrep "Dialog" )
# 			echo "${dialogRunningCheck}"

			# Dialog window closed because someone clicked Postpone
			if [ -z ${dialogRunningCheck} ];then
				Action="Stop"
				break
			fi
			
			# Waited longer than the $TimeOutinSec value
			if [ $SECONDS -gt ${TimeOutinSec} ];then
				Action="Timeout"
				break			
			fi
			
			# Recheck to see if anything changed
			checkForRunningProcessesThatNeedPatching
			updateListForRunningProducts
			sleep 3
						
		done

		# We are continuing on with the process
		
		# User quit open applications, we will continue patching
		if [ "${Action}" == "Patch" ]; then
			dialog_command "quit: "
		    runUpdates
			RunUpdates_EC=${UpdateResults}

		fi	

		# If the dialog simply timed-out, then so these things
		if [ "${Action}" == "Stop" ]; then
			echo "-----------------------------------"
			echo "User clicked Postpone button"
			echo "   Will skip all patching"
		fi	

		# If the dialog simply timed-out, then so these things
		if [ "${Action}" == "Timeout" ]; then
			dialog_command "quit: "
			echo "-----------------------------------"
			echo "Timeout waiting for user response"
			echo "   Will attempt to patch what can be patched"
			echo "-----------------------------------"
			# Attempt to run a full patch and update what can be updated
			# Some items are likely still running and will fail
			SU_EC="$(updateCLIAll)"
			echo "   RemoteUpdateManager Full Run. Exit Code: ${SU_EC}"
			RunUpdates_EC=${SU_EC}
		fi	
					
	else  # NO deferrals are remaining.
		echo "No deferrals, force update user."
		
		# Show user dialog. Allow them to quit apps.
		# If they don't, apps will be forced to quit
		
		# calculate dialog height
		dialogHeight=$((48 * ${AdobeRunArrayLength} + 285))
# 		echo ${dialogHeight}

		"${dialogApp}" --title "${TitlePrompt}" \
			--titlefont size=24 \
			--icon "${AdobeIcon}" --overlayicon warning \
			--message "${ForcedUpdatePrompt}" \
			--messagefont "size=16" \
			--button1text "${Update}" \
			--height ${dialogHeight} \
			--iconsize 128 \
			--quitoninfo \
			--quitkey x \
			--listitem "Loading list" \
			--alignment left \
			--ontop \
			--timer ${TimeOutinSec} \
			&
			
		checkForRunningProcessesThatNeedPatching
		createListForRunningProducts

		dialogRunningCheck=$( pgrep "Dialog" )
		
		while [[ ! -z ${dialogRunningCheck} ]]
		do
			dialogRunningCheck=$( pgrep "Dialog" )
# 			echo "${dialogRunningCheck}"
			
			if [ -z ${dialogRunningCheck} ];then
				Action="Stop"
				break
			fi

			checkForRunningProcessesThatNeedPatching
			updateListForRunningProducts
			sleep 3
		done

		if [ "${Action}" == "Stop" ];then
			forceQuitRunningApps
		fi
		
		runUpdates
		RunUpdates_EC=${UpdateResults}
    fi
fi

# Capture full RUM details afterwards

# Perform basic test for updates to see if we got everything
updateStatus=$(updatesAvailable)

# Capture full RUM details
RUM_Details=$( cat "${ListOfAdobeUpdates}" | tail -n +4 | sed -e '$ d' | awk '{$1="   "$1}1' )

echo "-----------------------------------"
echo "RUM Details at end:"
echo "${RUM_Details}"
echo "-----------------------------------"

updateRunCompleted

exit ${RunUpdates_EC}
