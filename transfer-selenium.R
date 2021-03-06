library(tidyverse)
library(RSelenium)
library(readr)
library(devtools)

#Source helper rselenium functions from github
devtools::source_url("https://github.com/hsteinberg/ccdph-functions/blob/master/general-use-rselenium-functions.R?raw=TRUE")
devtools::source_url("https://github.com/hsteinberg/ccdph-functions/blob/master/inedss-rselenium-functions.R?raw=TRUE")




#Helper function to get correct jurisdiction name
jurisdiction_select = read_csv("jurisdiction_selections_list.csv", col_types = cols())
get_jurisdiction_dropdown_name = function(jurisdiction){
  #Translate county name to health department name in select dropdown menu
  if(!exists("jurisdiction_select")){
    jurisdiction_select = read_csv("jurisdiction_selections_list.csv", col_types = cols())
  }
  
  if(toupper(jurisdiction) %in% toupper(jurisdiction_select$county)){ 
    #If county name, translate to dropdown selection name
    return(jurisdiction_select$selection[toupper(jurisdiction_select$county) == toupper(jurisdiction)])
    
    
  }else if(jurisdiction %in% jurisdiction_select$selection){
    #If already selection name, do nothing
    return(jurisdiction)
  }else{
    #If jurisdiction is not in either county name list or dropdown selection list
    message(paste(jurisdiction, "is not an acceptable selection."))
    return()
  }
  
}

#Helper function to fill in earliest report date/date public health receieved. 
#Returns NULL if neither date is filled in.
fill_in_report_dates = function(){
  wait_page("Case Summary")
  
  
  #Click into Reporting Source
  click_link("Reporting Source")  
  Sys.sleep(2)
  wait_page("Reporting Source")
  Sys.sleep(2)
  
  earliestReportMonth = get_text("#report", textbox = T)
  earliestReportDay = get_text(name.is("d1day"),textbox = T)
  earliestReportYear = get_text(name.is("d1year"), textbox = T)
  
  phReceivedMonth = get_text("#received", textbox = T)
  phReceivedDay = get_text(name.is("d2day"),textbox = T)
  phReceivedYear = get_text(name.is("d2year"), textbox = T)
  
  #If one date is filled in, just copy to the other
  if(phReceivedMonth !="" & earliestReportDay ==""){
    enter_text("#report", c(phReceivedMonth, phReceivedDay, phReceivedYear))
    Sys.sleep(2)

  }
  else if (phReceivedMonth =="" & earliestReportDay !=""){
    enter_text("#received", c(earliestReportMonth, earliestReportDay, earliestReportYear))
    Sys.sleep(2)

  }
  #If neither filled in, put error message for now
  else{
    message(paste(caseNumber, "needs Earliest Report Date or Date Public Health Received filled in.",
                  caseNumber, "has not been transferred."))
    click(value.is("Cancel"))
    return("DateNeeded")
    
  }
  
  #Make sure a reporting org is selected, if none, cancel
  if(dropdown_is_na("#reportingOrg") & get_text("#otherReportingOrg", textbox = T) == ""){
    click(value.is("Cancel"))
    return("ReportingOrgNeeded")
  }
  
  click(value.is("Save"))
  return(1)
}

#helper function to write to log
write_to_log = function(text, log=logfile){
  message(text)
  write(text, file = log, append = T)
}

#helper function to open New ELR case
open_new_elr_case = function(){
  wait_page("Case Summary") #need to start on case summary page
  
  #click "Laboratory Tests"
  click_link("Laboratory Tests")
  
  #click save
  click(value.is("Save"))
  
  wait_page("Case Summary")
}


#Final function for transferring cases
transfer = function(caseNumber, transferTo, 
                    logfile = paste0("daily-transferred-cases/", Sys.Date(), "transferred_log.txt"),
                    checkCook = T){
  
  #get transfer jurisdiction dropdown menu name
  jurisdiction = get_jurisdiction_dropdown_name(transferTo)
  
  #If jurisdiction not in jurisdiction_selections_list.csv, can't transfer
  if(is.null(jurisdiction)){
    write_to_log(paste(caseNumber, "not transferred because", transferTo, "is not a valid jurisdiction name."))
    return()
  }
  
  #search state case number
  search_scn(caseNumber)
  wait_page("Case Summary")
  
  #If not currently a CCDPH case, can't transfer
  jur = get_text(".NoBorderFull > table:nth-child(1) > tbody:nth-child(1) > tr:nth-child(1) > td:nth-child(2)")
  if(checkCook){
    if(jur != "Cook County Department of Public Health"){
      write_to_log(paste(caseNumber, "not transferred because already assigned to", jur))
      click(value.is("Close"))
      return()
    }
  }else{
    if(jur == jurisdiction){
      write_to_log(paste(caseNumber, "not transferred because already assigned to", jur))
      click(value.is("Close"))
      return()
    }
  }
  
  #If New ELR status, have to change to in-progress before you can transfer
  investigation_status = get_text("#container > div:nth-child(4) > form:nth-child(4) > table:nth-child(1) > tbody:nth-child(1) > tr:nth-child(3) > td:nth-child(1) > table:nth-child(2) > tbody:nth-child(1) > tr:nth-child(3) > td:nth-child(4)")
  if(investigation_status == "New ELR"){
    open_new_elr_case()
  }
  
  #If investigation status is Closed, write to log and move on
  if(investigation_status == "Closed"){
    write_to_log(paste(caseNumber, "not transferred because investigation status is Closed."))
    click(value.is("Close"))
    return()
  }
  
  #click transfer case
  click_link("Transfer Case")
  
  #Check to see if required fields are completed for transferring
  error = try(get_text("#container > div:nth-child(4) > form:nth-child(3) > table:nth-child(1) > tbody:nth-child(1) > tr:nth-child(4) > td:nth-child(1) > table:nth-child(1) > tbody:nth-child(1) > tr:nth-child(1) > td:nth-child(1) > center:nth-child(1)"),
              silent = T)
  
  #If your error box says something about invalid characters, write to log and skip
  if(grepl("invalid characters", error)){
    invalid = gsub("The following invalid conditions were found:\n\n", "", error)
    write_to_log(paste(caseNumber, "not transferred because", invalid))
    click(value.is("Cancel"))
    wait_page("Case Summary")
    click(value.is("Close"))
    return()
  }
  
  #If you get a box saying earliest report date or date lhd received is missing, go fix that
  if(grepl("Earliest Report Date and Date LHD Received are mandatory fields", error)){
    
    click("input[value = \"Cancel\"]")
    Sys.sleep(2)
    
    fill_in = fill_in_report_dates()
    
    #If neither earliest report date nor lhd received date is filled in, can't transfer
    if(fill_in == "DateNeeded"){
      write_to_log(paste(caseNumber, "not transferred because neither Earliest Report Date nor Date LHD Received are filled in."))
      wait_page("Case Summary")
      click(value.is("Close"))
      return()
    }
    if(fill_in == "ReportingOrgNeeded"){
      write_to_log(paste(caseNumber, "not transferred because Reporting Organization is not filled in."))
      wait_page("Case Summary")
      click(value.is("Close"))
      return()
    }
    
    #click transfer case
    click_link("Transfer Case")
    
  }
  

  
  
  #select jurisdiction from dropdown list
  Sys.sleep(2)
  select_drop_down(element = "#jurisdiction", selection = jurisdiction)
  Sys.sleep(2)
  
  #Transfer
  ifVisiblethenClick(value.is("Transfer"))

  #Accept alert
  acceptAlertwithWait()
  Sys.sleep(3)
  
  write_to_log(paste(caseNumber, "transferred to", jurisdiction))
}
