/*
 * Copyright (C) 2011 Klaus 'mrmoku' Kurzmann   <mok@fluxnetz.de>
 *               2011 Lukas 'slyon' Märdian     <lukasmaerdian@gmail.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 */

using FsoGsm;
using Gee;

namespace Gtm601
{
internal const uint NETWORK_COMM_TIMEOUT = 120;

public class PlusCOPS : AbstractAtCommand
{
    public int format;
    public int mode;
    public string oper;
    public string act;
    public int status;

    public FreeSmartphone.GSM.NetworkProvider[] providers;

    public enum Action
    {
        REGISTER_WITH_BEST_PROVIDER     = 0,
        REGISTER_WITH_SPECIFIC_PROVIDER = 1,
        UNREGISTER                      = 2,
        SET_FORMAT                      = 3,
    }

    public enum Format
    {
        ALPHANUMERIC                    = 0,
        ALPHANUMERIC_SHORT              = 1,
        NUMERIC                         = 2,
    }

    public PlusCOPS()
    {
        try
        {
            re = new Regex( """\+COPS:\ (?P<mode>\d)(,(?P<format>\d)?(,"(?P<oper>[^"]*)")?)?(?:,(?P<act>\d))?""" );
            tere = new Regex( """\((?P<status>\d),(?:"(?P<longname>[^"]*)")?,(?:"(?P<shortname>[^"]*)")?,"(?P<mccmnc>[^"]*)"(?:,(?P<act>\d))?\)""" );
        }
        catch ( GLib.RegexError e )
        {
            assert_not_reached(); // fail here if Regex is broken
        }
        prefix = { "+COPS: " };
    }

    public override void parse( string response ) throws AtCommandError
    {
        base.parse( response );
        mode = to_int( "mode" );
        format = to_int( "format" );
        oper = decodeString( to_string( "oper" ) );
        act = Constants.instance().networkProviderActToString( to_int( "act" ) );
    }

    public override void parseTest( string response ) throws AtCommandError
    {
        base.parseTest( response );
        var providers = new FreeSmartphone.GSM.NetworkProvider[] {};
        try
        {
            do
            {
                var p = FreeSmartphone.GSM.NetworkProvider(
                    Constants.instance().networkProviderStatusToString( to_int( "status" ) ),
                    decodeString( to_string( "longname" ) ),
                    decodeString( to_string( "shortname" ) ),
                    to_string( "mccmnc" ),
                    Constants.instance().networkProviderActToString( to_int( "act" ) ) );
                providers += p;
            }
            while ( mi.next() );
        }
        catch ( GLib.RegexError e )
        {
            FsoFramework.theLogger.error( @"Regex error: $(e.message)" );
            throw new AtCommandError.UNABLE_TO_PARSE( e.message );
        }
        this.providers = providers;
    }

    public string issue( Action action, Format format = Format.ALPHANUMERIC, int param = 0 )
    {
        if ( action == Action.REGISTER_WITH_BEST_PROVIDER )
        {
            return "+COPS=0,0";
        }
        else
        {
            return "+COPS=%d,%d,\"%d\"".printf( (int)action, (int)format, (int)param );
        }
    }

    public string query( Format format = Format.ALPHANUMERIC )
    {
        return "+COPS=%d,%d;+COPS?".printf( (int)Action.SET_FORMAT, (int)format );
    }

    public string test()
    {
        return "+COPS=?";
    }

    public override uint get_timeout() { return NETWORK_COMM_TIMEOUT; }
}

public class PlusCHUP : V250terCommand
{
    public PlusCHUP()
    {
        base( "+CHUP" );
    }
}

public class UnderscoreOWANCALL : V250terCommand
{
    public UnderscoreOWANCALL()
    {
        base( "_OWANCALL" );
    }

    public string issue( bool connect )
    {
        return connect ? "_OWANCALL=1,1,1" : "_OWANCALL=1,0,1";
    }
}

public class UnderscoreOWANDATA : AbstractAtCommand
{
    public bool connected;
    public string ip;
    public string gw;
    public string dns1;
    public string dns2;
    public string nbns1;
    public string nbns2;
    public string speed;

    public UnderscoreOWANDATA()
    {
        // some modems strip the leading zero for one-digit chars

        var str = """_OWANDATA: "(?P<connected>[01]), (?P<ip>[0-9.]+), (?P<gw>[0-9.]+), (?P<dns1>[0-9.]+), (?P<dns2>[0-9.]+), (?P<nbns1>[0-9.]+), (?P<nbns2>[0-9.]+), (?P<speed>\d+)""";
        try
        {
            re = new Regex( str );
        }
        catch ( GLib.RegexError e )
        {
            assert_not_reached(); // fail here if Regex is broken
        }
        prefix = { "_OWANDATA: " };
    }

    public override void parse( string response ) throws AtCommandError
    {
        base.parse( response );

        connected = to_int( "connected" ) == 1;
        ip = to_string( "ip" );
        gw = to_string( "gw" );
        dns1 = to_string( "dns1" );
        dns2 = to_string( "dns2" );
        nbns1 = to_string( "nbns1" );
        nbns2 = to_string( "nbns2" );
        speed = to_string( "speed" );
    }

    public string issue()
    {
        return "_OWANDATA?";
    }

//    public string query()
//    {
//        return "+CALA?";
//    }
}

/* register all custom at commands */
public void registerCustomAtCommands( HashMap<string,AtCommand> table )
{
    table[ "+COPS" ] = new PlusCOPS();
    table[ "H" ] = new PlusCHUP();
    table[ "_OWANCALL" ] = new UnderscoreOWANCALL();
    table[ "_OWANDATA" ] = new UnderscoreOWANDATA();
}

} // namespace Gtm601

// vim:ts=4:sw=4:expandtab
