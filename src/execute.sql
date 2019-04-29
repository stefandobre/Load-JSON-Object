/*------------------------------------------------------------------------------
 * Author       Stefan Dobre
 * Created      23.04.2019
 *
 * Description  Process Plugin to add a JSON Object to an APEX page already at render time
 *              The Object can be derrived from a SQL Query, PL/SQL Procedure or Static Text
 *              This plugin can be used for example to preload metadata for JS processes
 *
 * License      MIT 
 *------------------------------------------------------------------------------
 * Modification History
 *
 * 24.04.2019   v1.0 initial release
 */-----------------------------------------------------------------------------

function execute
    ( p_process in apex_plugin.t_process
    , p_plugin  in apex_plugin.t_plugin
    )
return apex_plugin.t_process_exec_result
as
    l_exec_result apex_plugin.t_process_exec_result;

    l_source                  varchar2(4000) := p_process.attribute_01;
    l_sql                     varchar2(4000) := p_process.attribute_02;
    l_json_sql                varchar2(4000) := p_process.attribute_03;
    l_plsql_json              varchar2(4000) := p_process.attribute_04;
    l_static_json             varchar2(4000) := p_process.attribute_05;
    l_javascript_variable     varchar2(4000) := p_process.attribute_06;

    --surrounded by quotes as it will be used a parameter
    l_js_literal              varchar2(4000) := apex_escape.js_literal(l_javascript_variable , '"' );
    
    --not surrounded by quotes, as it will be on the left side of an assignment
    l_js_literal_with_window  varchar2(4000) := apex_escape.js_literal('window.' || l_javascript_variable, null);
    
    l_clob                    clob;
    
    /* unfortunately htp.p can only handle varchars
     * this wrapper cuts a clob into 4000 byte chuncks and prints them one after the other
     */
    procedure htp_p_clob
        ( p_content clob
        )
    as
        l_offset number default 1;
    begin
         loop
           exit when l_offset > dbms_lob.getlength(p_content);
           htp.prn(dbms_lob.substr( p_content, 4000, l_offset ));
           l_offset := l_offset + 4000;
         end loop;
    end;
begin

    apex_plugin_util.debug_process
        ( p_plugin  => p_plugin
        , p_process => p_process
        );

    htp.p('<script>');
    
    /* wrapping the javascript in a self calling function
     * this helps not pollute the global namespace
     */
    htp.p('(function(){');
    
    /*
     * if we include this function in its own file 
     * or through apex_javascript.add_inline_code/ add_onload_code
     * it gets added at the end of the html file, but I already
     * want to use it now, so the regions and possibly included script tags
     * can already access the json object
     */ 
    htp.p('var createNestedObject=function(e,t){for(var r=(t=t.split(".")).length-1,a=0;a<r;++a){var n=t[a];n in e||(e[n]={}),e=e[n]}};');
    
    --creating the (possibly nested) object and sticking it onto the window object
    htp.p('createNestedObject(window, ' || l_js_literal || ');');
    
    --window.newObject = 
    htp.prn(l_js_literal_with_window || ' = ');

    --depending on the source, the actual json, not escaped will be htp.p'ed
    case l_source
        when 'sql' then
            /* in case of a simple sql statement we can use this internal function
             * it is undocumented but has been here forever it does the job
             * note that values over > 4000 characters will be cut off at 4000
             */
            apex_util.json_from_sql(l_sql);
        when 'jsonsql' then
            /* if the source is set to 'SQL Query Returning JSON Object'
             * we expect a query to return exactly 1 column with 1 row
             * ideally using something like select json_object() from ...
             */
            execute immediate l_json_sql into l_clob;
            htp_p_clob(l_clob);
        when 'plsql' then
            /* in case of PL/SQL, the developer is expected to use 
             * apex_json.open_object/ write, etc
             * By default, these calls already print to the http buffer
             */
            apex_json.initialize_output(p_http_header => false);
            execute immediate 'begin ' || l_plsql_json || ' end;';
        when 'static' then
            /* The developer can also provide a JSON as plain text
             */
            htp.prn(l_static_json);
    end case;
    
    --finishing off the assignment statement
    htp.p(';');
    
    --closing the self calling function
    htp.p('})();');
    
    htp.p('</script>');

    return l_exec_result;
end;