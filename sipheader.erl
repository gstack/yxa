-module(sipheader).
-export([to/1, from/1, contact/1, via/1, via_print/1, to_print/1,
	 contact_print/1, auth_print/1, auth_print/2, auth/1, comma/1,
	 httparg/1, cseq/1, cseq_print/1, via_params/1, contact_params/1,
	 build_header/1, dict_to_param/1, param_to_dict/1, dialogueid/1,
	 get_tag/1, topvia/1, via_sentby/1, get_client_transaction_id/1,
	 get_server_transaction_id/1, get_via_branch/1]).

comma(String) ->
    comma([], String, false).

% comma(Parsed, Rest, Inquote)

comma(Parsed, [$\\, Char | Rest], true) ->
    comma(Parsed ++ [$\\, Char], Rest, true);
comma(Parsed, [$" | Rest], false) ->
    comma(Parsed ++ [$"], Rest, true);
comma(Parsed, [$" | Rest], true) ->
    comma(Parsed ++ [$"], Rest, false);
comma(Parsed, [$, | Rest], false) ->
    [string:strip(Parsed, both) | comma([], Rest, false)];
comma(Parsed, [Char | Rest], Inquote) ->
    comma(Parsed ++ [Char], Rest, Inquote);
comma(Parsed, [], false) ->
    [string:strip(Parsed, both)].

% name-addr = [ display-name ] "<" addr-spec ">"
% display-name = *token | quoted-string


% {Displayname, URL}

to([String]) ->
    name_header(String).

from([String]) ->
    name_header(String).

contact([]) ->
    [];
    
contact([String | Rest]) ->
    Headers = comma(String),
    lists:append(lists:map(fun(H) ->
				   parse_contact(H)
			   end, Headers),
		 contact(Rest)).

parse_contact("'*'") ->
    {none, {wildcard, []}};

parse_contact("*") ->
    {none, {wildcard, []}};

parse_contact("'*';" ++ ParamStr) ->
    Parameters = string:tokens(ParamStr, ";"),
    {none, {wildcard, Parameters}};

parse_contact("*;" ++ ParamStr) ->
    Parameters = string:tokens(ParamStr, ";"),
    {none, {wildcard, Parameters}};

parse_contact(String) ->
    name_header(String).

contact_params({_, {wildcard, Parameters}}) ->
    param_to_dict(Parameters);
contact_params({_, {_, _, _, _, Parameters}}) ->
    param_to_dict(Parameters).

via([]) ->
    [];
via([String | Rest]) ->
    Headers = comma(String),
    lists:append(lists:map(fun(H) ->
				   [Protocol, Sentby] = string:tokens(H, " "),
				   [Hostport | Parameters ] = string:tokens(Sentby, ";"),
				   {Protocol, sipurl:parse_hostport(Hostport), Parameters}
			   end, Headers),
		 via(Rest)).

topvia(Header) ->
    case via(keylist:fetch("Via", Header)) of
	[] -> none;
	[TopVia | _] -> TopVia;
	_ -> error
    end.

print_parameters([]) ->
    "";
print_parameters([A | B]) ->
    ";" ++ A ++ print_parameters(B).

via_print(Via) ->
    lists:map(fun(H) ->
		      {Protocol, {Host, Port}, Parameters} = H,
		      Protocol ++ " " ++ sipurl:print_hostport(Host, Port) ++ print_parameters(Parameters)
	      end, Via).

via_params({Protocol, Hostport, Parameters}) ->
    param_to_dict(Parameters).

contact_print(Contact) ->
    lists:map(fun(H) ->
		      name_print(H)
	      end, Contact).

to_print(To) ->
    name_print(To).

name_print({_, wildcard, Parameters}) ->
    sipurl:print({wildcard, Parameters});
    
name_print({none, URI}) ->
    "<" ++ sipurl:print(URI) ++ ">";

name_print({Name, URI}) ->
    "\"" ++ Name ++ "\" <" ++ sipurl:print(URI) ++ ">".

unquote([$" | QString]) ->
    Index = string:chr(QString, $"),
    string:substr(QString, 1, Index - 1);

unquote(QString) ->
    QString.

name_header(String) ->
    %logger:log(debug, "n: ~p", [String]),
    Index1 = string:rchr(String, $<),
    case Index1 of
	0 ->
	    % No "<", just an URI?
	    URI = sipurl:parse(String),
	    {none, URI};
	_ ->
	    Index2 = string:rchr(String, $>),
	    URL = string:substr(String, Index1 + 1, Index2 - Index1 - 1),
	    URI = sipurl:parse(URL),
	    Displayname = parse_displayname(string:substr(String, 1, Index1 - 1)),
	    {Displayname, URI}
    end.

parse_displayname(String) ->
    LeftQuoteIndex = string:chr(String, $"),
    case LeftQuoteIndex of
	0 ->
	    empty_displayname(string:strip(String));
	_ ->
	    TempString = string:substr(String, LeftQuoteIndex + 1),
	    RightQuoteIndex = string:chr(TempString, $"),
	    empty_displayname(string:substr(TempString, 1, RightQuoteIndex - 1))
    end.

empty_displayname([]) ->
    none;
empty_displayname(Name) ->
    Name.

auth_print(Auth) ->
    auth_print(Auth, false).

auth_print(Auth, Stale) ->
    {Realm, Nonce, Opaque} = Auth,
    ["Digest realm=\"" ++ Realm ++ "\", nonce=\"" ++ Nonce ++ "\", opaque=\"" ++ Opaque ++ "\"" ++
     case Stale of
	 true ->
	     ", stale=true";
	 _ ->
	     ""
     end
    ].

auth(["GSSAPI " ++ String]) ->
    Headers = comma(String),
    L = lists:map(fun(A) ->
			  H = string:strip(A,left),
			  Index = string:chr(H, $=),
			  Name = string:substr(H, 1, Index - 1),
			  Value = string:substr(H, Index + 1),
			  
			  {Name, unquote(Value)}
		  end, Headers),
    dict:from_list(L);

auth(["Digest " ++ String]) ->
    Headers = comma(String),
    L = lists:map(fun(A) ->
			  H = string:strip(A,left),
			  Index = string:chr(H, $=),
			  Name = string:substr(H, 1, Index - 1),
			  Value = string:substr(H, Index + 1),
			  
			  {Name, unquote(Value)}
		  end, Headers),
    dict:from_list(L).

unescape([]) ->
    [];
unescape([$%, C1, C2 | Rest]) ->
    [hex:from([C1, C2]) | unescape(Rest)];
unescape([C | Rest]) ->
    [C | unescape(Rest)].

param_to_dict(Param) ->
    L = lists:map(fun(A) ->
			  H = string:strip(A,left),
			  Index = string:chr(H, $=),
			  case Index of
			      0 ->
			          {httpd_util:to_lower(H), ""};
			      _ ->
				  Name = httpd_util:to_lower(string:substr(H, 1, Index - 1)),
				  Value = string:substr(H, Index + 1),
				  {Name, unescape(Value)}
			  end
		  end, Param),
    dict:from_list(L).    

dict_to_param(Dict) ->
    list_to_parameters(dict:to_list(Dict)).
    
list_to_parameters([]) ->
    [];
list_to_parameters([{Key, Value}]) ->
    [Key ++ "=" ++ Value];
list_to_parameters([{Key, Value} | Rest]) ->
    [Key ++ "=" ++ Value | list_to_parameters(Rest)].
    

httparg(String) ->
    Headers = string:tokens(String, "&"),
    param_to_dict(Headers).

cseq([String]) ->
    case string:tokens(String, " ") of
	[Seq, Method] ->
	    {Seq, Method};
	_ ->
	    {unparseable, String}
    end.

cseq_print({Seq, Method}) ->
    Seq ++ " " ++ Method.

print_one_header(_, _, []) ->
    [];
print_one_header(Name, LCName, [Value | Rest]) ->
    case util:casegrep(Name, ["Allow", "Supported", "Require",
			      "Proxy-Require"]) of
	true ->
	    [Name ++ ": " ++ util:join(lists:append([Value], Rest), ", ")];
	_ ->
	    lists:append([Name ++ ": " ++ Value], print_one_header(Name, LCName, Rest))
    end.

build_header(Header) ->
    case catch build_header_unsafe(Header) of
	{'EXIT', E} ->
	    logger:log(error, "=ERROR REPORT==== failed to build header ~p,~nfrom build_header_unsafe :~n~p", [Header, E]),
	    throw({siperror, 500, "Server Internal Error"});
	Res ->
	    Res
    end.

build_header_unsafe(Header) ->
    Lines = keylist:map(fun print_one_header/3, Header),
    lists:map(fun(H) ->
			util:concat(H, "\r\n")
		end, Lines).

get_tag([String]) ->
    Index = string:chr(String, $>),
    ParamStr = string:substr(String, Index + 1),
    ParamList = string:tokens(ParamStr, ";"),
    ParamDict = param_to_dict(ParamList),
    case dict:find("tag", ParamDict) of
	error ->
	    none;
	{ok, Tag} ->
	    Tag
    end.

dialogueid(Header) ->
    get_dialogid(Header).

via_sentby(Via) ->
    {Protocol, {Host, Port}, Parameters} = Via,
    {Protocol, Host, Port}.

get_server_transaction_id(Request) ->
    case catch safe_get_server_transaction_id(Request) of
	{'EXIT', E} ->
	    logger:log(error, "=ERROR REPORT==== from get_server_transaction_id(~p) :~n~p", [Request, E]),
	    error;
	Id ->
	    Id
    end.

get_client_transaction_id(Response) ->
    case catch safe_get_client_transaction_id(Response) of
	{'EXIT', E} ->
	    logger:log(error, "=ERROR REPORT==== from get_client_transaction_id(~p) :~n~p", [Response, E]),
	    error;
	Id ->
	    Id
    end.

safe_get_server_transaction_id(Request) ->
    {Method, URI, Header, Body} = Request,
    TopVia = sipheader:topvia(Header),
    Branch = get_via_branch(TopVia),
    case Branch of
	"z9hG4bK" ++ RestOfBranch ->
	    get_server_transaction_id_3261(Method, TopVia);
	_ ->
	    get_server_transaction_id_2543(Request, TopVia)
    end.

safe_get_client_transaction_id(Response) ->
    {_, _, Header, _} = Response,
    TopVia = sipheader:topvia(Header),
    Branch = get_via_branch(TopVia),
    {_, CSeqMethod} = sipheader:cseq(keylist:fetch("CSeq", Header)),
    {Branch, CSeqMethod}.

get_server_transaction_id_3261("ACK", TopVia) ->
    % The transaction for an ACK has method INVITE. RFC3261 17.2.3
    get_server_transaction_id_3261("INVITE", TopVia);
get_server_transaction_id_3261(Method, TopVia) ->
    Branch = get_via_branch(TopVia),
    SentBy = via_sentby(TopVia),
    {Branch, SentBy, Method}.

get_server_transaction_id_2543({"ACK", URI, Header, _}, TopVia) ->
    % When using this function, you have to make sure the To-tag
    % of this ACK matches the To-tag of the response you think this
    % might be the ACK for! RFC3261 17.2.3
    [CallID] = keylist:fetch("Call-ID", Header),
    {_, CSeqNum} = sipheader:cseq(keylist:fetch("CSeq", Header)),
    FromTag = sipheader:get_tag(keylist:fetch("From", Header)),
    ToTag = sipheader:get_tag(keylist:fetch("To", Header)),
    {URI, FromTag, CallID, CSeqNum, TopVia};

get_server_transaction_id_2543({Method, URI, Header, _}, TopVia) ->
    [CallID] = keylist:fetch("Call-ID", Header),
    CSeq = sipheader:cseq(keylist:fetch("CSeq", Header)),
    FromTag = sipheader:get_tag(keylist:fetch("From", Header)),
    ToTag = sipheader:get_tag(keylist:fetch("To", Header)),
    {URI, ToTag, FromTag, CallID, CSeq, TopVia}.

get_dialogid(Header) ->
    [CallID] = keylist:fetch("Call-ID", Header),
    FromTag = sipheader:get_tag(keylist:fetch("From", Header)),
    ToTag = sipheader:get_tag(keylist:fetch("To", Header)),
    {CallID, FromTag, ToTag}.

get_via_branch({_, {ViaHostname, ViaPort}, Parameters}) ->
    case dict:find("branch", sipheader:param_to_dict(Parameters)) of
	error ->
	    none;
	{ok, "z9hG4bK-yxa-" ++ RestOfBranch} ->
	    case sipserver:get_env(detect_loops, true) of
		true ->
		    case string:rstr(RestOfBranch, "-o") of
			0 ->
			    "z9hG4bK-yxa-" ++ RestOfBranch;
			Index when integer(Index) ->
			    % Return branch without Yxa loop cookie
			    "z9hG4bK-yxa-" ++ string:substr(RestOfBranch, 1, Index - 1)
		    end;
		_ ->
		    "z9hG4bK-yxa-" ++ RestOfBranch
	    end;
	{ok, Branch} ->
	    Branch
    end;
get_via_branch(_) ->
    none.
