/**
 * -- Mickey's DBus Utility V2 --
 *
 * Copyright (C) 2009-2010 Michael 'Mickey' Lauer <mlauer@vanille-media.de>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 **/

//=========================================================================//
using GLib;

//=========================================================================//
const string DBUS_BUS_NAME  = "org.freedesktop.DBus";
const string DBUS_OBJ_PATH  = "/";
const string DBUS_INTERFACE = "org.freedesktop.DBus";
const string DBUS_INTERFACE_INTROSPECTABLE = "org.freedesktop.DBus.Introspectable";

//=========================================================================//
MainLoop mainloop;

public string formatMessage( DBus.RawMessage msg )
{
#if DEBUG
    debug( @"message has signature: $(msg.get_signature())" );
#endif

    DBus.RawMessageIter iter = DBus.RawMessageIter();
    if ( msg.iter_init( iter ) )
    {
        var signature = iter.get_signature();

        var result = "( ";
        result += formatResult( iter );

        while ( iter.has_next() )
        {
            iter.next();
            result += @", $(formatResult(iter))";
        }
        return result + " )";
    }
    else
    {
        return "()";
    }
}

public string formatResult( DBus.RawMessageIter iter, int depth = 0 )
{
    var signature = iter.get_signature();
#if DEBUG
    debug( @"signature for this iter = $signature" );
#endif
    /*
     * Dictionary container
     */
    if ( signature[0] == 'a' && signature[1] == '{' )
    {
        DBus.RawMessageIter subiter = DBus.RawMessageIter();
        iter.recurse( subiter );
        var result = "{ ";
        do
        {
            result += formatResult( subiter, depth+1 );
            if ( subiter.has_next() )
            {
                result += ", ";
            }
            subiter.next();
        } while ( subiter.has_next() );
        result += "}";
        return result;
    }

    /*
     * Array container
     */
    if ( signature[0] == 'a' )
    {
#if DEBUG
        debug( "array" );
#endif
        DBus.RawMessageIter subiter = DBus.RawMessageIter();
        iter.recurse( subiter );
        var result = "[ ";
        do
        {
            result += formatResult( subiter, depth+1 );
            if ( subiter.has_next() )
            {
                result += ", ";
            }
            subiter.next();
        } while ( subiter.has_next() );
        result += " ]";
        return result;
    }
    
    /*
     * Struct Entry
     */
    if ( signature[0] == '(' && signature[signature.length-1] == ')' )
    {
        DBus.RawMessageIter subiter = DBus.RawMessageIter();
        iter.recurse( subiter );
        var result = ") ";
        do
        {
            result += formatResult( subiter, depth+1 );
            if ( subiter.has_next() )
            {
                result += ", ";
            }
            subiter.next();
        } while ( subiter.has_next() );
        result += " )";
        return result;
    }

    /*
     * Dictionary Entry
     */
    if ( signature[0] == '{' && signature[signature.length-1] == '}' )
    {
        DBus.RawMessageIter subiter = DBus.RawMessageIter();
        iter.recurse( subiter );
        var result = " ";
        result += formatResult( subiter, depth+1 );
        result += " : ";
        subiter.next();
        result += formatResult( subiter, depth+1 );
        return result;
    }
    /*
     * Variant
     */
    if ( signature == "v" )
    {
        DBus.RawMessageIter subiter = DBus.RawMessageIter();
        iter.recurse( subiter );
        var result = " ";
        result += formatResult( subiter, depth+1 );
        return result;
    }

    /*
     * Simple Type
     */
    return formatSimpleType( signature, iter );
}

static string formatSimpleType( string signature, DBus.RawMessageIter iter )
{
    switch ( signature )
    {
        case "b":
            bool b = false;
            iter.get_basic( &b );
            return b.to_string();
        case "i":
            int i = 0;
            iter.get_basic( &i );
            return i.to_string();
        case "s":
            unowned string s = null;
            iter.get_basic( &s );
            return @"\"$s\"";
        case "o":
            unowned string s = null;
            iter.get_basic( &s );
            return @"op'$s'";
        default:
#if DEBUG
            critical( @"signature $signature not yet handled" );
#endif
            return @"($signature ???)";
    }
}

//===========================================================================
public class Argument : Object
{
    public Argument( string name, string typ )
    {
        this.name = name;
        this.typ = typ;
    }

    public bool appendToCall( string arg, DBus.RawMessage message )
    {
#if DEBUG
        debug( @"trying to parse argument $name of type $typ delivered as $arg" );
#endif
        switch ( typ )
        {
            case "s":
                assert( message.append_args( DBus.RawType.STRING, ref arg ) );
                break;

            case "i":
                var value = arg.to_int();
                assert( message.append_args( DBus.RawType.INT32, ref value ) );
                break;

            default:
                stderr.printf( "Unsupported type $typ\n" );
                return false;
        }
        return true;
    }

    public string name;
    public string typ;
}

//===========================================================================
public class Entity : Object
{
    public enum Typ
    {
        METHOD,
        SIGNAL,
        PROPERTY
    }

    public Entity( string name, Typ typ )
    {
        this.name = name;
        this.typ = typ;
    }

    public string to_string()
    {
        string line = "";

        switch ( typ )
        {
            case Typ.METHOD:   line = "[METHOD]    %s(%s) -> (%s)";
            break;
            case Typ.SIGNAL:   line = "[SIGNAL]    %s(%s)";
            break;
            case Typ.PROPERTY: line = "[PROPERTY]  %s(%s)";
            break;
            default:
                assert_not_reached();
        }

        string inargs = "";

        foreach ( var arg in inArgs )
        {
            inargs += " %s:%s,".printf( arg.typ, arg.name );
        }
        if ( inArgs.length() > 0 )
            ( (char[]) inargs )[inargs.length-1] = ' ';

        string outargs = "";

        if ( outArgs.length() > 0 )
        {
            foreach ( var arg in outArgs )
            {
                outargs += " %s:%s,".printf( arg.typ, arg.name );
            }
            ( (char[]) outargs )[outargs.length-1] = ' ';
        }

        line = line.printf( name, inargs, outargs );
        return line;
    }

    public string name;
    public Typ typ;
    public List<Argument> inArgs;
    public List<Argument> outArgs;
}

//===========================================================================
public class Introspection : Object
{
    private string[] _xmldata;

    public List<string> nodes;
    public List<string> interfaces;
    public List<Entity> entitys;

    private string iface;
    private Entity entity;

    public Introspection( string xmldata )
    {
        //message( "introspection object created w/ xmldata: %s", xmldata );

        MarkupParser parser = { startElement, null, null, null, null };
        var mpc = new MarkupParseContext( parser, MarkupParseFlags.TREAT_CDATA_AS_TEXT, this, null );

        foreach ( var line in xmldata.split( "\n" ) )
        {
            if ( line[1] != '!' || line[0] != '"' )
            {
                //message( "dealing with line '%s'", line );
                mpc.parse( line, line.length );
            }
        }
    }

    public void handleAttributes( string[] attribute_names, string[] attribute_values )
    {
        string name = "none";
        string direction = "in";
        string typ = "?";

        for ( int i = 0; i < attribute_names.length; ++i )
        {
            switch ( attribute_names[i] )
            {
                case "name":
                    name = attribute_values[i];
                    break;
                case "direction":
                    direction = attribute_values[i];
                    break;
                case "type":
                    typ = attribute_values[i];
                    break;
            }
        }

        var arg = new Argument( name, typ );
        if ( direction == "in" )
            entity.inArgs.append( arg );
        else
            entity.outArgs.append( arg );
    }

    public void startElement( MarkupParseContext context,
                              string element_name,
                              string[] attribute_names,
                              string[] attribute_values ) throws MarkupError
    {
        //message( "start element '%s'", element_name );

        foreach ( var attribute in attribute_names )
        {
            //message( "attribute name '%s'", attribute );
        }
        foreach ( var value in attribute_values )
        {
            //message( "attribute value '%s'", value );
        }

        switch ( element_name )
        {
            case "node":
                if ( attribute_names != null &&
                     attribute_names[0] == "name" &&
                     attribute_values != null &&
                     attribute_values[0][0] != '/' &&
                     attribute_values[0] != "" )
                {
                    nodes.append( attribute_values[0] );
                }
                break;
            case "interface":
                iface = attribute_values[0];
                interfaces.append( iface );
                break;
            case "method":
                entity = new Entity( "%s.%s".printf( iface, attribute_values[0] ), Entity.Typ.METHOD );
                entitys.append( entity );
                break;
            case "signal":
                entity = new Entity( "%s.%s".printf( iface, attribute_values[0] ), Entity.Typ.SIGNAL );
                entitys.append( entity );
                break;
            case "property":
                entity = new Entity( "%s.%s".printf( iface, attribute_values[0] ), Entity.Typ.PROPERTY );
                entitys.append( entity );
                handleAttributes( attribute_names, attribute_values );
                break;
            case "arg":
                assert( entity != null );
                handleAttributes( attribute_names, attribute_values );
                break;
            default:
                assert_not_reached();
        }
    }
}

//=========================================================================//
class Commands : Object
{
    DBus.Connection bus;
    dynamic DBus.Object busobj;

    public Commands( DBus.BusType bustype )
    {
        try
        {
            bus = DBus.Bus.get( bustype );
            busobj = bus.get_object( DBUS_BUS_NAME, DBUS_OBJ_PATH, DBUS_INTERFACE );
        }
        catch ( DBus.Error e )
        {
            critical( "dbus error: %s", e.message );
        }
    }

    private string appendPidToBusName( string name )
    {
        try
        {
            return "%s (%s)".printf( name, busobj.GetConnectionUnixProcessID( "%s".printf( name ) ) );
        }
        catch ( DBus.Error e )
        {
            debug( "%s", e.message );
            return "%s (unknown)".printf( name );
        }
    }

    public void listBusNames()
    {
        string[] names = busobj.ListNames();
        List<string> sortednames = new List<string>();

        if ( showAnonymous )
        {
            foreach ( var name in names )
            {
                sortednames.insert_sorted( showPIDs ? appendPidToBusName( name ) : name, strcmp );
            }
        }
        else
        {
            foreach ( var name in names )
            {
                if ( !name.has_prefix( ":" ) )
                {
                    sortednames.insert_sorted( showPIDs ? appendPidToBusName( name ) : name, strcmp );
                }
            }
        }

        foreach ( var name in sortednames )
        {
            stdout.printf( "%s\n", name );
        }
    }

    public void listObjects( string busname, string path = "/" )
    {
        dynamic DBus.Object o = bus.get_object( busname, path, DBUS_INTERFACE_INTROSPECTABLE );
        stdout.printf( "%s\n", path );

        try
        {
            var idata = new Introspection( o.Introspect() );
            foreach ( var node in idata.nodes )
            {
                //message ( "node = '%s'", node );
                var nextnode = ( path == "/" ) ? "/%s".printf( node ) : "%s/%s".printf( path, node );
                //message( "nextnode = '%s'", nextnode );
                listObjects( busname, nextnode );
            }
        }
        catch ( DBus.Error e )
        {
            stderr.printf( "Error: %s\n", e.message );
            return;
        }
    }

    public void listInterfaces( string busname, string path )
    {
        dynamic DBus.Object o = bus.get_object( busname, path, DBUS_INTERFACE_INTROSPECTABLE );

        try
        {
            var idata = new Introspection( o.Introspect() );
            if ( idata.entitys.length() == 0 )
            {
                stderr.printf( "Error: No introspection data at object '%s'\n", path );
                return;
            }
            foreach ( var entity in idata.entitys )
            {
                stdout.printf( "%s\n", entity.to_string() );
            }
        }
        catch ( DBus.Error e )
        {
            stderr.printf( "Error: %s\n", e.message );
            return;
        }
    }

    public bool callMethod( string busname, string path, string method, string[] args )
    {
        dynamic DBus.Object o = bus.get_object( busname, path, DBUS_INTERFACE_INTROSPECTABLE );

        try
        {
            var idata = new Introspection( o.Introspect() );
            if ( idata.entitys.length() == 0 )
            {
                stderr.printf( "Error: No introspection data at object %s\n", path );
                return false;
            }

            foreach ( var entity in idata.entitys )
            {
                if ( entity.typ == Entity.Typ.METHOD && entity.name == method )
                {
                    var methodWithPoint = method.rchr( -1, '.' );
                    var baseMethod = methodWithPoint.substring( 1 );
                    var iface = method.substring( 0, method.length - baseMethod.length - 1 );

                    // check number of input params
                    if ( args.length != entity.inArgs.length() )
                    {
                        stderr.printf( "Error: Need %u params, supplied %u\n", entity.inArgs.length(), args.length );
                        return false;
                    }

                    // construct DBus Message arg by arg
                    var call = new DBus.RawMessage.call( busname, path, iface, baseMethod );
                    int i = 0;
                    foreach ( var inarg in entity.inArgs )
                    {
                        if ( inarg.appendToCall( args[i++], call ) )
                        {
#if DEBUG
                            debug( @"Argument $i parsed from commandline ok" );
#endif
                        }
                        else
                        {
                            return false;
                        }
                    }

                    DBus.RawError error = DBus.RawError();
                    DBus.RawConnection* connection = bus.get_connection();
                    DBus.RawMessage reply = connection->send_with_reply_and_block( call, 100000, ref error );

                    if ( error.is_set() )
                    {
#if DEBUG
                        stderr.printf( @"Method call OK. Result:\nDBus Error $(error.name): $(error.message)\n" );
#else
                        stderr.printf( @"$(error.name): $(error.message)\n" );
#endif
                    }
                    else
                    {
#if DEBUG
                        stderr.printf( @"Method call OK. Result:\n$(formatMessage(reply))\n" );
#else
                        stderr.printf( @"$(formatMessage(reply))\n" );
#endif
                    }
                    return true;
                }
            }

            stderr.printf( @"Error: No method $method found at $path\n" );
        }
        catch ( DBus.Error e )
        {
            stderr.printf( "Error: %s\n", e.message );
            return false;
        }
        return false;
    }

    public DBus.RawHandlerResult signalHandler( DBus.RawConnection conn, DBus.RawMessage message )
    {
#if DEBUG
        debug( "got message w/ type %d", message.get_type() );
#endif
        if ( message.get_type() != DBus.RawMessageType.SIGNAL )
        {
            return DBus.RawHandlerResult.NOT_YET_HANDLED;
        }

        var line = "[SIGNAL] %s.%s %s".printf(
          message.get_interface(),
          message.get_member(),
          formatMessage( message ) );
        stdout.printf( @"$line\n" );

        return DBus.RawHandlerResult.HANDLED;
    }

    private string formatRule( string busname, string objectpath, string iface )
    {
        var rule = "type='signal'";

        if ( busname != "*" )
        {
            rule += @",sender='$busname'";
        }

        if ( objectpath != "*" )
        {
            rule += @",path='$objectpath'";
        }

        if ( iface != "*" )
        {
            rule += @",interface='$iface'";
        }

        /*

        if (data->member)
                offset += snprintf(rule + offset, size - offset,
                                ",member='%s'", data->member);
        if (data->argument)
                snprintf(rule + offset, size - offset,
                                ",arg0='%s'", data->argument);
        */
        return rule;
    }

    public void listenForSignals( string busname = "*", string objectpath = "*", string iface = "*" )
    {
        DBus.RawConnection* connection = bus.get_connection();
        connection->add_filter( signalHandler );
        DBus.RawError error = DBus.RawError();
        connection->add_match( formatRule( busname, objectpath, iface ), ref error );
        ( new MainLoop() ).run();
    }

    private void performCommandFromShell( string commandline )
    {
        stderr.printf( " *** interactive mode not implemented yet\n" );        
    }

    private void completion( string[] s, int a, int b )
    {
        debug( "completion" );
    }

    public void launchShell()
    {
        Readline.initialize();
        Readline.readline_name = "fso-term";
        Readline.terminal_name = Environment.get_variable( "TERM" );

        Readline.History.read( "%s/.fso-term.history".printf( Environment.get_variable( "HOME" ) ) );
        Readline.History.max_entries = 512;

        Readline.completion_display_matches_hook = completion;
        Readline.completer_word_break_characters = " ";
        Readline.parse_and_bind( "tab: complete" );

        var done = false;

        while ( !done )
        {
            var line = Readline.readline( "MDBUS2> " );
            if ( line == null ) // ctrl-d
            {
                done = true;
            }
            else
            {
                Readline.History.add( line );
                if ( line != "" )
                {
                    performCommandFromShell( line );
                }
            }
        }
        stderr.printf( "Good bye!\n" );
        Readline.History.write( "%s/.mdbus2.history".printf( Environment.get_variable( "HOME" ) ) );
    }
}

//=========================================================================//
bool showAnonymous;
bool listenerMode;
bool showPIDs;
bool useSystemBus;
bool interactive;

const OptionEntry[] options =
{
    { "show-anonymous", 'a', 0, OptionArg.NONE, ref showAnonymous, "Show anonymous names", null },
    { "show-pids", 'p', 0, OptionArg.NONE, ref showPIDs, "Show unix process IDs", null },
    { "listen", 'l', 0, OptionArg.NONE, ref listenerMode, "Listen for signals", null },
    { "system", 's', 0, OptionArg.NONE, ref useSystemBus, "Use System Bus", null },
    { "interactive", 'i', 0, OptionArg.NONE, ref interactive, "Enter interactive shell", null },
    { null }
};

//=========================================================================//
int main( string[] args )
{
    try
    {
        var opt_context = new OptionContext( "- Mickey's DBus Utility V2" );
        opt_context.set_help_enabled( true );
        opt_context.add_main_entries( options, null );
        opt_context.parse( ref args );
    }
    catch ( OptionError e )
    {
        stdout.printf( "%s\n", e.message );
        stdout.printf( "Run '%s --help' to see a full list of available command line options.\n", args[0] );
        return 1;
    }

    var commands = new Commands( useSystemBus ? DBus.BusType.SYSTEM : DBus.BusType.SESSION );

    switch ( args.length )
    {
        case 1:
            if ( interactive )
            {
                commands.launchShell();
                return 0;
            }

            if (!listenerMode)
                commands.listBusNames();
            else
                commands.listenForSignals();
            break;

        case 2:
            if ( !listenerMode )
                commands.listObjects( args[1] );
            else
                commands.listenForSignals( args[1] );
            break;

        case 3:
            if ( !listenerMode )
                commands.listInterfaces( args[1], args[2] );
            else
                commands.listenForSignals( args[1], args[2] );
            break;

        default:
            assert( args.length > 3 );

            if ( listenerMode )
            {
                commands.listenForSignals( args[1], args[2], args[3] );
                return 0;
            }

            string[] restargs = {};
            for ( int i = 4; i < args.length; ++i )
            {
                restargs += args[i];
            }
            var ok = commands.callMethod( args[1], args[2], args[3], restargs );
            return ok ? 0 : -1;
            break;
    }

    /*
    if (version)
    {
        stdout.printf ("Vala %s\n", Config.PACKAGE_VERSION);
        return 0;
    }

    if (sources == null) {
        stderr.printf ("No source file specified.\n");
        return 1;
    }
    */

    return 0;
}

