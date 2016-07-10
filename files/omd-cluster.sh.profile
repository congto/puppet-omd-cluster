alias nodestatus='crm_mon -1 | GREP_COLORS="mt=01;32" egrep --color=auto $(hostname)"|$"'
alias nodestandby='crm node standby'
alias nodeonline='crm node online'
nodestatus
