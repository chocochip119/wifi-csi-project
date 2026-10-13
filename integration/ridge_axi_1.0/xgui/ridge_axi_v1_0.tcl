# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "CORE_ID" -parent ${Page_0}
  ipgui::add_param $IPINST -name "N_CLASSES" -parent ${Page_0}
  ipgui::add_param $IPINST -name "N_FEATURES" -parent ${Page_0}
  ipgui::add_param $IPINST -name "N_WWORDS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "N_XWORDS" -parent ${Page_0}


}

proc update_PARAM_VALUE.CORE_ID { PARAM_VALUE.CORE_ID } {
	# Procedure called to update CORE_ID when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CORE_ID { PARAM_VALUE.CORE_ID } {
	# Procedure called to validate CORE_ID
	return true
}

proc update_PARAM_VALUE.N_CLASSES { PARAM_VALUE.N_CLASSES } {
	# Procedure called to update N_CLASSES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.N_CLASSES { PARAM_VALUE.N_CLASSES } {
	# Procedure called to validate N_CLASSES
	return true
}

proc update_PARAM_VALUE.N_FEATURES { PARAM_VALUE.N_FEATURES } {
	# Procedure called to update N_FEATURES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.N_FEATURES { PARAM_VALUE.N_FEATURES } {
	# Procedure called to validate N_FEATURES
	return true
}

proc update_PARAM_VALUE.N_WWORDS { PARAM_VALUE.N_WWORDS } {
	# Procedure called to update N_WWORDS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.N_WWORDS { PARAM_VALUE.N_WWORDS } {
	# Procedure called to validate N_WWORDS
	return true
}

proc update_PARAM_VALUE.N_XWORDS { PARAM_VALUE.N_XWORDS } {
	# Procedure called to update N_XWORDS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.N_XWORDS { PARAM_VALUE.N_XWORDS } {
	# Procedure called to validate N_XWORDS
	return true
}


proc update_MODELPARAM_VALUE.N_FEATURES { MODELPARAM_VALUE.N_FEATURES PARAM_VALUE.N_FEATURES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.N_FEATURES}] ${MODELPARAM_VALUE.N_FEATURES}
}

proc update_MODELPARAM_VALUE.N_CLASSES { MODELPARAM_VALUE.N_CLASSES PARAM_VALUE.N_CLASSES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.N_CLASSES}] ${MODELPARAM_VALUE.N_CLASSES}
}

proc update_MODELPARAM_VALUE.N_WWORDS { MODELPARAM_VALUE.N_WWORDS PARAM_VALUE.N_WWORDS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.N_WWORDS}] ${MODELPARAM_VALUE.N_WWORDS}
}

proc update_MODELPARAM_VALUE.N_XWORDS { MODELPARAM_VALUE.N_XWORDS PARAM_VALUE.N_XWORDS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.N_XWORDS}] ${MODELPARAM_VALUE.N_XWORDS}
}

proc update_MODELPARAM_VALUE.CORE_ID { MODELPARAM_VALUE.CORE_ID PARAM_VALUE.CORE_ID } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CORE_ID}] ${MODELPARAM_VALUE.CORE_ID}
}

