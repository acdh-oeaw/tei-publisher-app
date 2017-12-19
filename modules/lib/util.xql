(:
 :
 :  Copyright (C) 2017 Wolfgang Meier
 :
 :  This program is free software: you can redistribute it and/or modify
 :  it under the terms of the GNU General Public License as published by
 :  the Free Software Foundation, either version 3 of the License, or
 :  (at your option) any later version.
 :
 :  This program is distributed in the hope that it will be useful,
 :  but WITHOUT ANY WARRANTY; without even the implied warranty of
 :  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 :  GNU General Public License for more details.
 :
 :  You should have received a copy of the GNU General Public License
 :  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 :)
xquery version "3.1";

module namespace tpu="http://www.tei-c.org/tei-publisher/util";


import module namespace config="http://www.tei-c.org/tei-simple/config" at "../config.xqm";
import module namespace nav="http://www.tei-c.org/tei-simple/navigation" at "../navigation.xql";

declare function tpu:parse-pi($doc as document-node(), $view as xs:string?) {
    tpu:parse-pi($doc, $view, ())
};

declare function tpu:parse-pi($doc as document-node(), $view as xs:string?, $odd as xs:string?) {
    let $odd := ($odd, $config:odd)[1]
    let $oddAvailable := doc-available($config:odd-root || "/" || $odd)
    let $odd := if ($oddAvailable) then $odd else $config:default-odd
    let $default := map {
        "view": ($view, $config:default-view)[1],
        "odd": $odd,
        "depth": $config:pagination-depth,
        "fill": $config:pagination-fill,
        "type": nav:document-type($doc/*)
    }
    let $pis :=
        map:new(
            for $pi in $doc/processing-instruction("teipublisher")
            let $analyzed := analyze-string($pi, '([^\s]+)\s*=\s*"(.*?)"')
            for $match in $analyzed/fn:match
            let $key := $match/fn:group[@nr="1"]/string()
            let $value := $match/fn:group[@nr="2"]/string()
            return
                if ($key = "view" and $value != $view) then
                    ()
                else
                    map:entry($key, $value)
        )
    return
        map:new(($default, $pis))
};
