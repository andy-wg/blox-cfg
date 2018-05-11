# /* Blox is an Opensource Session Border Controller
#  * Copyright (c) 2015-2018 "Blox" [http://www.blox.org]
#  * 
#  * This file is part of Blox.
#  * 
#  * Blox is free software: you can redistribute it and/or modify
#  * it under the terms of the GNU General Public License as published by
#  * the Free Software Foundation, either version 3 of the License, or
#  * (at your option) any later version.
#  * 
#  * This program is distributed in the hope that it will be useful,
#  * but WITHOUT ANY WARRANTY; without even the implied warranty of
#  * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  * GNU General Public License for more details.
#  * 
#  * You should have received a copy of the GNU General Public License
#  * along with this program. If not, see <http://www.gnu.org/licenses/> 
#  */


# ----------- global configuration parameters ------------------------
include_file "blox-glob.cfg"

include_file "blox-listen.cfg"
include_file "blox-listen-local.cfg"

include_file "blox-tls.cfg"

# ------------------ module loading ----------------------------------
include_file "blox-modules.cfg"

# ----------------- setting module-specific parameters ---------------
include_file "blox-modparam.cfg"

startup_route {
    subscribe_event("E_SCRIPT_EVENT", "udp:BLOX_SUBSCRIBE_HOST:BLOX_SUBSCRIBE_PORT");
    avp_db_query("SELECT codec FROM  blox_codec","$avp(codec)");
    cache_store("local", "allomtscodec", "$avp(codec)");
}

route[ALLOMTSLOAD] {
    avp_db_query("SELECT codec FROM  blox_codec","$avp(codec)");
    cache_store("local", "allomtscodec", "$avp(codec)");
}

# main routing logic
route {
    xlog("L_INFO", "BLOX_DBG::: blox.cfg: Got $rm req:$ru from:$fu to:$tu dst:$du ua:$ua\n" );
    xlog("L_INFO", "BLOX_DBG::: blox.cfg: contact:$ct callid:$ci src:$si:$sp ==> rcv:$Ri:$Rp\n");

    # initial sanity checks
    if (pcre_match_group("$ua", "0")) { #Group: 0 is blacklist
        xlog("L_INFO", "BLOX_DBG::: blox.cfg: Dropping SIP scanner $ua\n");
        exit;
    }

    if (msg:len >= MAX_SIP_MSG_LENGTH ) {
        xlog("L_ERR", "BLOX_DBG: blox.cfg: Too BIG $rm $ml: $fu/$ru/$si/$du/$retcode\n" );
        sl_send_reply("513", "Message too big");
        exit;
    };

    if (!mf_process_maxfwd_header("MAX_SIP_MAXFWD")) {
        sl_send_reply("483","Too Many Hops");
        exit;
    };

    $avp(SIPProfile) = "sip:" + $Ri + ":" + $Rp + ";transport=" + $pr;
    
    xdbg("BLOX_DBG: blox.cfg: Getting Profile for $avp(SIPProfile)\n");
    if(cache_fetch("local","LAN:$avp(SIPProfile)",$avp(LAN))) { #/* Try loading from cache */
        xdbg("BLOX_DBG: blox.cfg: Got Profile info from cache LAN:$avp(SIPProfile) $avp(WAN)\n");
        $avp(LANIP) = $(avp(SIPProfile){uri.host});
        $avp(LANPORT) = $(avp(SIPProfile){uri.port});
    } else if(cache_fetch("local","WAN:$avp(SIPProfile)",$avp(WAN))) { #/* Try loading from cache */
        xdbg("BLOX_DBG: blox.cfg: Got Profile info from cache WAN:$avp(SIPProfile) $avp(WAN)\n");
        $avp(WANIP) = $(avp(SIPProfile){uri.host});
        $avp(WANPORT) = $(avp(SIPProfile){uri.port});
    } else if(avp_db_load("$avp(SIPProfile)","$avp(LAN)/blox_profile_config")) { #/* Try loading from db */
        $avp(LANIP) = $(avp(SIPProfile){uri.host});
        $avp(LANPORT) = $(avp(SIPProfile){uri.port});
        cache_store("local","LAN:$avp(SIPProfile)", "$avp(LAN)");
        #cache_store("local","$avp(LAN)", "$avp(SIPProfile)"); #/* Store the reverse of key/value too */
    } else if (avp_db_load("$avp(SIPProfile)","$avp(WAN)/blox_profile_config")) { #/* Try loading from db */
        $avp(WANIP) = $(avp(SIPProfile){uri.host});
        $avp(WANPORT) = $(avp(SIPProfile){uri.port});
        cache_store("local","WAN:$avp(SIPProfile)", "$avp(WAN)");
        #cache_store("local","$avp(WAN)", "$avp(SIPProfile)"); #/* Store the reverse of key/value too */
    }

    if(!($avp(LAN) || $avp(WAN))) {
        xlog("L_INFO", "BLOX_DBG::: blox.cfg: Unknown SIP Profile $avp(SIPProfile) ==> $avp(LAN) $avp(WAN)\n");
        sl_send_reply("603", "Declined");
        exit;
    }


    if($avp(LAN)) {
        route(READ_LAN_PROFILE);
        $avp(SHMP) = $(avp(LANProfile){uri.param,shmp});
    } else {
        route(READ_WAN_PROFILE);
        $avp(SHMP) = $(avp(WANProfile){uri.param,shmp});
    }
    if($avp(SHMP)==""){$avp(SHMP)=null;}
    
    $var(SHMPACT) = null ;
    if($avp(SHMP)) {
            route(SIP_HEADER_MANIPULATE,$avp(SHMP));
    } 

    xdbg("BLOX_DBG::: blox.cfg: LAN SIP Profile $avp(LANProfile) ==> $avp(LAN)\n");
    xdbg("BLOX_DBG::: blox.cfg: WAN SIP Profile $avp(WANProfile) ==> $avp(WAN)\n");

    $var(nat96) = null;
    $var(nat40) = null;
    $var(nat32) = null;
    $var(nat8)  = null;
    $var(nat3)  = null;

    if ($ct) {
        #address in Contact is compared against source IP address of signaling
        #Port in Contact is compared against source port of signaling 
        if(nat_uac_test("64") && nat_uac_test("32")) {  
            $var(nat96) = 96 ;
        }

        #address in Contact is compared against source IP address of signaling
        #SDP is searched for occurrence of RFC1918 / RFC6598 addresses 
        if(nat_uac_test("32") && nat_uac_test("8")) {
            $var(nat40) = 40 ;
        }

        #address in Contact is compared against source IP address of signaling
        if(nat_uac_test("32")) {
            $var(nat32)  = 32 ;
        }

        #SDP is searched for occurrence of RFC1918 / RFC6598 addresses 
        if(nat_uac_test("8")) {
            $var(nat8)  = 8;
        }

        #Contact header field is searched for occurrence of RFC1918 / RFC6598 addresses.
        #"received" test: address in Via is compared against source IP address of signaling 
        if(client_nat_test("1") && client_nat_test("2")) {
            $var(nat3)  = 3 ;
        }

        xlog("L_INFO","BLOX_DBG: $rm: $ru: $ct: $si: $hdr(Via): NAT:$var(nat96):$var(nat40):$var(nat32):$var(8):$var(nat3):");

        $var(ct) = $ct ; # /* Original contact */
        $var(cturi) = $ct.fields(uri) ; # /* Original contact */
        $var(fixnat) = 1 ;

        if($avp(WAN)) { # /* Fix NAT On WAN Request */
            if($proto == "tcp" || $proto == "tls") {
                if($var(nat32) == null) {
                    $var(fixnat) = null ;
                }
            } else if($var(nat3) == null) {
                    $var(fixnat) = null ;
            }
            if($var(fixnat)) {
                if(is_method("REGISTER")) {
                    xlog("L_INFO","BLOX_DBG: $rm: FIX NAT $var(fixnat)");
                    fix_nated_register(); /* will set not just contact, update received address to db */
                } else {
                    fix_nated_contact(); # /* Contact header manipuation further should be avoided */
                }
            }
        }
    }

    force_rport();

    xdbg("BLOX_DBG: blox.cfg: Got ($pr:$Ri:$Rp) $avp(SIPProfile): Index:$avp(LAN):$avp(WAN):");

    if (is_method("OPTIONS") ) {
        xdbg("BLOX_DBG: blox.cfg: Not support OPTIONS\n");
        append_hf("Allow: INVITE, ACK, REFER, NOTIFY, CANCEL, BYE, REGISTER" );
        sl_send_reply("405", "Method Not Allowed");
        exit;
    }

    if(method == "REGISTER") {
        route(ROUTE_REGISTER);
    };

    #FIXME: performance on db needs to be optimized
    #if (is_method("BYE") || is_method("CANCEL")) {
    #    $avp(cfgparam) = "cfgparam" ;
    #    avp_db_delete("$hdr(call-id)","$avp($avp(cfgparam))") ;
    #}

    # subsequent messages withing a dialog should take the
    # path determined by record-routing
    if (loose_route()) {
        xdbg("BLOX_DBG: blox.cfg: PRE-ROUTING SIP Method $rm received from $fu $si $sp to $ru ($avp(rcv))\n");
        # mark routing logic in request
        append_hf("P-hint: rr-enforced\r\n");
        if (is_method("BYE|CANCEL")) {
            if($dlg_val(MediaProfileID)) {
                $avp(MediaProfileID) = $dlg_val(MediaProfileID) ;
                $avp(setid) = $(avp(MediaProfileID){s.int}) ;
                if($avp(setid)) {
                    rtpengine_delete();
                }
                xlog("L_INFO", "BLOX_DBG::: blox.cfg: Mediaprofile stopping the $avp(MediaProfileID)\n");
            }
            $avp(resource) = "resource" + "-" + $ft ;
            route(DELETE_ALLOMTS_RESOURCE);
        };
	if(!is_method("NOTIFY|MESSAGE")) {
        if($avp(LAN)) {
            route(LAN2WAN);
        } else {
            route(WAN2LAN);
        }
        exit;
	}
    };

    $avp(dupreq) = null;
    if (has_totag() && ((uri == myself)||(from_uri == myself)) && is_method("INVITE|ACK|BYE|UPDATE|REFER|NOTIFY|PRACK|INFO")) {
         xdbg("BLOX_DBG: blox.cfg: MATCHING DIALOG\n");
         if(match_dialog()) {
            xdbg("BLOX_DBG: blox.cfg: MATCHED DIALOG req:$ru du:$du\n");
            xdbg("BLOX_DBG: blox.cfg: In-Dialog tophide dir: $DLG_dir - up: $dlg_val(ucontact) down: $dlg_val(dcontact) \n");
            if (is_method("BYE")) {
                if($dlg_val(MediaProfileID)) {
                    $avp(MediaProfileID) = $dlg_val(MediaProfileID) ;
                    $avp(setid) = $(avp(MediaProfileID){s.int}) ;
                    if($avp(setid)) {
                        rtpengine_delete();
                    }
                    xlog("L_INFO", "BLOX_DBG::: blox.cfg: Mediaprofile stopping the $avp(MediaProfileID)\n");
                }
                $avp(resource) = "resource" + "-" + $ft ;
                route(DELETE_ALLOMTS_RESOURCE);
                $avp(resource) = "resource" + "-" + $tt ;
                route(DELETE_ALLOMTS_RESOURCE);
            };
            if($avp(LAN)) {
                route(LAN2WAN);
            } else {
                route(WAN2LAN);
            }
            exit;
         };
    };


    if ((uri==myself || from_uri==myself)) {
        if (method == "CANCEL") {
            if(t_check_trans()) { #/* Packet not retransmitted */
                route(ROUTE_CANCEL);
            }
            exit;
        }

        if ( method == "ACK" ) { #already dialog handled, this should be dropped
            if(t_check_trans()) { #/* Packet not retransmitted */
                route(ROUTE_ACK);
            }
            exit;
        }

        t_check_trans();

        if(method == "INVITE") {
            route(ROUTE_INVITE);
        }

        if(method == "NOTIFY") { /* Only REFER-NOTIFY, Not SUBSCRIBE */
           route(ROUTE_NOTIFY);
        }

        if(method == "SUBSCRIBE") {
            route("ROUTE_SUBSCRIBE");
        }

        if(method == "PUBLISH") {
            route("ROUTE_PUBLISH");
            exit;
        };

        if(method == "MESSAGE") { /* Only REFER-MESSAGE, Not SUBSCRIBE */
           route(ROUTE_MESSAGE);
        }
    }

    drop();
    xlog("L_INFO", "BLOX_DBG::: blox.cfg: Dropping SIP Method $rm received from $fu $si $sp to $ru ($avp(rcv))\n"); /* Dont know what to do */
    exit;
}

route[READ_WAN_PROFILE] {
    if($avp(WAN)) {
        if(cache_fetch("local","$avp(WAN)",$avp(WANProfile))) {
            xdbg("BLOX_DBG: blox-invite.cfg: Loaded from cache $avp(WAN): $avp(WANProfile)\n");
        } else if (avp_db_load("$avp(WAN)","$avp(WANProfile)/blox_profile_config")) {
            cache_store("local","$avp(WAN)","$avp(WANProfile)");
            xdbg("BLOX_DBG: blox-invite.cfg: Stored in cache $avp(WAN): $avp(WANProfile)\n");
        } else {
            $avp(WANProfile) = null;
            xlog("L_INFO","BLOX_DBG: blox.cfg: Drop MESSAGE $ru from $si : $sp\n" );
            drop(); # /* Default 5060 open to accept packets from WAN side, but we don't process it */
            exit;
        }
    }
}

route[READ_LAN_PROFILE] {
    if($avp(LAN)) {
        if(cache_fetch("local","$avp(LAN)",$avp(LANProfile))) {
            xdbg("BLOX_DBG: blox.cfg: Loaded from cache $avp(LAN): $avp(LANProfile)\n");
        } else if (avp_db_load("$avp(LAN)","$avp(LANProfile)/blox_profile_config")) {
            cache_store("local","$avp(LAN)","$avp(LANProfile)");
            xdbg("BLOX_DBG: blox.cfg: Stored in cache $avp(LAN): $avp(LANProfile)\n");
        } else {
            $avp(LANProfile) = null;
            xlog("L_INFO","BLOX_DBG: blox.cfg: Drop MESSAGE $ru from $si : $sp\n" );
            drop(); # /* Default 5060 open to accept packets from LAN side, but we don't process it */
            exit;
        }
    }
}
route[READ_ENUM] {
    $var(uuid) = "ENUM"+$param(1);
    if(cache_fetch("local","$var(uuid)",$avp(ENUM))) {
        xdbg("BLOX_DBG: blox.cfg: Loaded from cache $var(uuid): $avp(ENUM)\n");
    } else if (avp_db_load("$var(uuid)","$avp(ENUM)/blox_enum")) {
        cache_store("local","$var(uuid)","$avp(ENUM)");
        xdbg("BLOX_DBG: blox.cfg: Stored in cache $var(uuid): $avp(ENUm)\n");
    } else {
        $avp(ENUM) = null;
        xlog("L_INFO","BLOX_DBG: blox.cfg: ENUM is not configured  \n" );
    }
}

route[READ_HEADER] {
    $var(match) = $param(1);
    $var(HEADER) = null ;

    switch($var(match)) {
        case "$rU":    
            $var(HEADER) = $rU;
            break;
        case "$tU":    
            $var(HEADER) = $tU;
            break;
        case "$fU":    
            $var(HEADER) = $fU;
            break;
        default :
            xlog(" Requested Condition did not matched  \n");   
    }   
}

# ----------- Experimentation routers ------------------------
failure_route[missed_call] {
    if (t_was_cancelled()) {
        $avp(MediaProfileID) = $dlg_val(MediaProfileID) ;
        $avp(setid) = $(avp(MediaProfileID){s.int}) ;
        if($avp(setid)) {
            rtpengine_delete();
        }
        $avp(resource) = "resource" + "-" + $ft ;
        route(DELETE_ALLOMTS_RESOURCE);
        exit;
    }
}

failure_route[UAC_AUTH_FAIL] {
    xdbg("BLOX_DBG: blox.cfg: In failure_route UAC_AUTH_FAIL");
        
    if (t_check_status("40[17]")) {
        # have we already tried to authenticate?
        if (isflagset(88)) {
            t_reply("503","Authentication failed");
            exit;
        }
        if(uac_auth()) {
            $avp(uuid) = "cseq-" + $ft ;
            setflag(88);
            xdbg("BLOX_DBG: blox.cfg: Return code is $retcode");
            if(!cache_fetch("local","$avp(uuid)",$avp(CSEQ_OFFSET))) {
                $avp(CSEQ_OFFSET) = 1;
            }
            $var(toffset) = $avp(CSEQ_OFFSET) ;
            $var(offset) = $(var(toffset){s.int}) ;
            $var(c) = $(cs{s.int}) + $var(offset);
            subst("/CSeq: (.*) (.*)$/CSeq: $var(c) \2/");
            cache_store("local","$avp(uuid)","$avp(CSEQ_OFFSET)");

            $avp(uuid) = "auth-" + $ft ;
            cache_store("local","$avp(uuid)","$avp(auth)");

            xdbg("BLOX_DBG: blox.cfg: Got Challenged $var(c): $avp(CSEQ_OFFSET)\n");
            t_on_failure("UAC_AUTH_FAIL");
            append_branch();

            xdbg("BLOX_DBG: blox.cfg: failure_route the cseq offset for $mb\n") ;
            #t_relay();
        } else {
            xlog("L_INFO", "BLOX_DBG::: blox.cfg: uac_auth failed\n") ;
        }
    }
}

###########################################################################################
# ----------- SIP Method based routers ------------------------
include_file "blox-media.cfg"
include_file "blox-register.cfg"
include_file "blox-invite.cfg"
include_file "blox-cancel.cfg"
include_file "blox-bye.cfg"
include_file "blox-ack.cfg"
include_file "blox-notify.cfg"
include_file "blox-subscribe.cfg"
include_file "blox-publish.cfg"
include_file "blox-message.cfg"
include_file "blox-userblacklist.cfg"
###########################################################################################
# ----------- SBC Feature routers ------------------------
include_file "blox-lcr.cfg"
include_file "blox-cac.cfg"
include_file "blox-enum.cfg"
include_file "blox-sip-header-manipulation.cfg"
include_file "blox-lb.cfg"
include_file "blox-domain.cfg"
include_file "blox-bypass-tls.cfg"
###########################################################################################
# ----------- SIP Profile based routers without MTS ------------------------
import_file  "blox-allomts-dummy.cfg"
import_file  "blox-lan2wan.cfg"
import_file  "blox-wan2lan.cfg"
###########################################################################################
# ----------- AlloMTS Transcoding routers ------------------------
import_file  "blox-allomts.cfg"
import_file  "blox-lan2wan-allomts.cfg"
import_file  "blox-wan2lan-allomts.cfg"
###########################################################################################
# ----------- Addon Module ------------------------
import_file  "blox-addon-humbug.cfg"
###########################################################################################
