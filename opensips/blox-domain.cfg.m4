route[BLOX_DOMAIN] {
    $var(uuid) = "DOM" + $param(1) + ":" + $rd + ":" + $rp;

    $avp(DEFURI) = null;    
    $avp(SUBURI) = null;    
    if (method == "SUBSCRIBE") {
        if(cache_fetch("local","$var(uuid)",$avp(SUBURI))) {
            xdbg("Loaded from cache $var(uuid): $avp(SUBURI)\n");
        } else if (avp_db_load("$var(uuid)","$avp(SUBURI)/blox_domain")) {
            cache_store("local","$var(uuid)","$avp(SUBURI)");
            xdbg("Stored in cache $var(uuid): $avp(SUBURI)\n");
        } else {
            xlog("L_WARN", "BLOX_DBG::: $rm METHOD Domain name not configured in blox for $var(uuid)\n" );
        }
    }

    if(cache_fetch("local","$var(uuid)",$avp(DEFURI))) {
        xdbg("Loaded from cache $var(uuid): $avp(DEFURI)\n");
    } else if (avp_db_load("$var(uuid)","$avp(DEFURI)/blox_domain")) {
        cache_store("local","$var(uuid)","$avp(DEFURI)");
        xdbg("Stored in cache $var(uuid): $avp(DEFURI)\n");
    } else {
        xlog("L_WARN", "BLOX_DBG::: $rm METHOD Domain name not configured in blox for $var(uuid)\n" );
    }

    $du = $avp(DEFURI) ;
    xlog("L_WARN", "BLOX_DBG::: Domain name $var(uuid) routed to $avp(DEFURI) \n");
}
#dnl vim: set ts=4 sw=4 tw=0 et :
