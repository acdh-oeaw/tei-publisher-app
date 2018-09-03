(:
 :
 :  Copyright (C) 2018 Wolfgang Meier
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

declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace deploy="http://www.tei-c.org/tei-publisher/generator";
declare namespace expath="http://expath.org/ns/pkg";
declare namespace repo="http://exist-db.org/xquery/repo";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";

declare option output:method "json";
declare option output:media-type "application/javascript";

declare variable $deploy:EXPATH_DESCRIPTOR :=
    <package xmlns="http://expath.org/ns/pkg"
        version="0.1" spec="1.0">
        <dependency package="http://exist-db.org/apps/shared"/>
        <dependency package="http://existsolutions.com/apps/tei-publisher"/>
    </package>
;

declare variable $deploy:REPO_DESCRIPTOR :=
    <meta xmlns="http://exist-db.org/xquery/repo">
        <description></description>
        <author></author>
        <website></website>
        <status>beta</status>
        <license>GNU-LGPL</license>
        <copyright>true</copyright>
        <type>application</type>
        <target></target>
        <prepare>pre-install.xql</prepare>
        <finish>post-install.xql</finish>
        <permissions user=""
            password=""
            group="tei"
            mode="rw-rw-r--"/>
    </meta>
;

declare variable $deploy:ANT_FILE :=
    <project default="xar">
        <xmlproperty file="expath-pkg.xml"/>
        <property name="project.version" value="${{package(version)}}"/>
        <property name="build.dir" value="build"/>
        <target name="xar">
            <mkdir dir="${{build.dir}}"/>
            <zip basedir="." destfile="${{build.dir}}/${{project.app}}-${{project.version}}.xar"
                excludes="${{build.dir}}/*"/>
        </target>
    </project>;
        
declare function deploy:expand-ant($nodes as node()*, $json as map(*)) {
    for $node in $nodes
    return
        typeswitch($node)
            case element(project) return
                <project name="{$json?abbr}">
                    { $node/@* except $node/@name }
                    { deploy:expand-ant($node/node(), $json) }
                </project>
            case element(property) return
                if ($node/@name = "project.app") then
                    <property name="project.app" value="{$json?abbr}"/>
                else
                    $node
            case element() return
                element { node-name($node) } {
                    $node/@*,
                    deploy:expand-ant($node/node(), $json)
                }
            default return
                $node
};

declare function deploy:expand-expath-descriptor($pkg as element(expath:package), $json as map(*)) {
    <package xmlns="http://expath.org/ns/pkg" spec="1.0" version="0.1"
        name="{$json?uri}" abbrev="{$json?abbrev}">
        <title>{$json?title}</title>
        { $pkg/* }
    </package>
};

declare function deploy:expand-repo-descriptor($meta as element(repo:meta), $json as map(*)) {
    <meta xmlns="http://exist-db.org/xquery/repo">
        <description>{$json?title}</description>
        { $meta/(repo:author|repo:status|repo:license|repo:copyright|repo:type|repo:prepare|repo:finish) }
        <target>{$json?abbrev}</target>
        <permissions user="{$json?owner}" password="{$json?password}"
            group="tei" mode="rw-rw-r--"/>
    </meta>
};

declare function deploy:check-user($json as map(*)) as xs:string+ {
    let $user := $json?owner
    let $group := "tei"
    let $create :=
        if (xmldb:exists-user($user)) then
            if (index-of(xmldb:get-user-groups($user), $group)) then
                ()
            else
                xmldb:add-user-to-group($user, $group)
        else
            xmldb:create-user($user, $json?password, $group, ())
    return
        ($user, $group)
};

declare function deploy:mkcol-recursive($collection, $components, $userData as xs:string*, $permissions as xs:string?) {
    if (exists($components)) then
        let $permissions :=
            if ($permissions) then
                deploy:set-execute-bit($permissions)
            else
                "rwxr-x---"
        let $newColl := xs:anyURI(concat($collection, "/", $components[1]))
        return (
            if (not(xmldb:collection-available($newColl))) then
                xmldb:create-collection($collection, $components[1])
            else
                (),
            deploy:mkcol-recursive($newColl, subsequence($components, 2), $userData, $permissions)
        )
    else
        ()
};

declare function deploy:mkcol($path, $userData as xs:string*, $permissions as xs:string?) {
    let $path := if (starts-with($path, "/db/")) then substring-after($path, "/db/") else $path
    return
        deploy:mkcol-recursive("/db", tokenize($path, "/"), $userData, $permissions)
};

declare function deploy:set-execute-bit($permissions as xs:string) {
    replace($permissions, "(..).(..).(..).", "$1x$2x$3x")
};

declare function deploy:create-collection($collection as xs:string, $userData as xs:string+, $permissions as xs:string) {
    let $target := collection($collection)
    return
        if ($target) then
            $target
        else
            deploy:mkcol($collection, $userData, $permissions)
};

declare function deploy:copy-collection($target as xs:string, $source as xs:string, $userData as xs:string+, $permissions as xs:string) {
    let $null := deploy:mkcol($target, $userData, $permissions)
    return
    if (exists(collection($source))) then (
        for $resource in xmldb:get-child-resources($source)
        let $targetPath := xs:anyURI(concat($target, "/", $resource))
        return (
            xmldb:copy($source, $target, $resource)
        ),
        for $childColl in xmldb:get-child-collections($source)
        return
            deploy:copy-collection(concat($target, "/", $childColl), concat($source, "/", $childColl), $userData, $permissions)
    ) else
        ()
};

declare function deploy:store-xconf($collection as xs:string?, $json as map(*)) {
    let $xconf:=
        <collection xmlns="http://exist-db.org/collection-config/1.0">
            <index xmlns:tei="http://www.tei-c.org/ns/1.0" xmlns:xs="http://www.w3.org/2001/XMLSchema">
                <fulltext default="none" attributes="false"/>
                <lucene>
                    <text qname="{$json?index}">
                        <ignore qname="{$json?index}"/>
                    </text>
                    <text qname="tei:head"/>
                    <text match="//tei:sourceDesc/tei:biblFull/tei:titleStmt/tei:title"/>
                    <text match="//tei:fileDesc/tei:titleStmt/tei:title"/>
                    <text qname="dbk:section"/>
                    <text qname="dbk:title"/>
                </lucene>
            </index>
        </collection>
    return
        xmldb:store($collection, "collection.xconf", $xconf, "text/xml")
};


declare function deploy:store-ant($collection as xs:string?, $json as map(*)) {
    let $descriptor := deploy:expand-ant($deploy:ANT_FILE, $json)
    return (
        xmldb:store($collection, "build.xml", $descriptor, "text/xml")
    )
};

declare function deploy:store-expath-descriptor($collection as xs:string?, $json as map(*)) {
    let $descriptor := deploy:expand-expath-descriptor($deploy:EXPATH_DESCRIPTOR, $json)
    return (
        xmldb:store($collection, "expath-pkg.xml", $descriptor, "text/xml")
    )
};

declare function deploy:store-repo-descriptor($collection as xs:string?, $json as map(*)) {
    let $descriptor := deploy:expand-repo-descriptor($deploy:REPO_DESCRIPTOR, $json)
    return (
        xmldb:store($collection, "repo.xml", $descriptor, "text/xml")
    )
};

declare function deploy:expand($collection as xs:string, $resource as xs:string, $parameters as map(*)) {
    if (util:binary-doc-available($collection || "/" || $resource)) then
        let $code :=
            let $doc := util:binary-doc($collection || "/" || $resource)
            return
                util:binary-to-string($doc)
        let $expanded :=
            fold-right(map:keys($parameters), $code, function($key, $in) {
                try {
                    replace($in, $key, "$1" || $parameters($key) || ";", "m")
                } catch * {
                    $in
                }
            })
        return
            xmldb:store($collection, $resource, $expanded)
    else
        ()
};

declare function deploy:store-libs($target as xs:string, $userData as xs:string+, $permissions as xs:string) {
    let $path := system:get-module-load-path()
    for $lib in ("autocomplete.xql", "index.xql", "view.xql", xmldb:get-child-resources($path)[starts-with(., "navigation")],
        xmldb:get-child-resources($path)[ends-with(., "query.xql")])
    return (
        xmldb:copy($path, $target || "/modules", $lib)
    ),
    let $target := $target || "/modules/lib"
    let $source := system:get-module-load-path() || "/lib"
    return
        deploy:copy-collection($target, $source, $userData, $permissions)
};

declare function deploy:copy-odd($collection as xs:string, $json as map(*)) {
    (:  Copy the selected ODD and its dependencies  :)
    let $target := $collection || "/resources/odd"
    let $mkcol := deploy:mkcol($target, ("tei", "tei"), "rwxr-x---")
    for $file in ("tei_simplePrint.odd", "teipublisher.odd", $json?odd || ".odd")
    let $source := doc($config:odd-root || "/" || $file)
    return
        xmldb:store($target, $file, $source, "application/xml")
};

declare function deploy:create-transform($collection as xs:string) {
    deploy:mkcol($collection || "/transform", ("tei", "tei"), "rwxr-x---"),
    for $file in ("master.fo.xml", "page-sequence.fo.xml")
    let $template := repo:get-resource("http://existsolutions.com/apps/tei-publisher-lib", "content/" || $file)
    return
        xmldb:store($collection || "/transform", $file, $template, "text/xml")
};


declare function deploy:create-app($collection as xs:string, $json as map(*)) {
    let $create :=
        deploy:create-collection($collection, ($json?owner, "tei"), "rw-rw-r--")
    let $base := substring-before(system:get-module-load-path(), "/modules")
    let $dataRoot := if ($json?data-collection) then $json?data-collection else "data"
    let $dataRoot :=
        if (starts-with($dataRoot, "/")) then
            $dataRoot
        else
            '\$config:app-root || "/' || $dataRoot || '"'
    let $replacements := map {
        "^(.*\$config:default-view :=).*;$": '"' || $json?default-view || '"',
        "^(.*\$config:search-default :=).*;$": '"' || $json?index || '"',
        "^(.*\$config:data-root\s*:=).*;$": $dataRoot,
        "^(.*\$config:default-odd :=).*;$": '"' || $json?odd || '.odd"',
        "^(.*module namespace pm-web\s*=).*;$": '"http://www.tei-c.org/pm/models/' || $json?odd || '/web/module" at "../transform/' ||
            $json?odd || '-web-module.xql"',
        "^(.*module namespace pm-print\s*=).*;$": '"http://www.tei-c.org/pm/models/' || $json?odd || '/fo/module" at "../transform/' ||
            $json?odd || '-print-module.xql"',
        "^(.*module namespace pm-latex\s*=).*;$": '"http://www.tei-c.org/pm/models/' || $json?odd || '/latex/module" at "../transform/' ||
            $json?odd || '-latex-module.xql"',
        "^(.*module namespace pm-epub\s*=).*;$": '"http://www.tei-c.org/pm/models/' || $json?odd || '/epub/module" at "../transform/' ||
            $json?odd || '-epub-module.xql"'
    }
    let $created := (
        deploy:store-expath-descriptor($collection, $json),
        deploy:store-repo-descriptor($collection, $json),
        deploy:store-ant($collection, $json),
        deploy:store-xconf($collection, $json),
        deploy:copy-collection($collection, $base || "/templates/basic", ($json?owner, "tei"), "rw-rw-r--"),
        deploy:expand($collection || "/modules", "config.xqm", $replacements),
        deploy:expand($collection || "/modules", "pm-config.xql", $replacements),
        deploy:store-libs($collection, ($json?owner, "tei"), "rw-rw-r--"),
        deploy:copy-odd($collection, $json),
        deploy:create-transform($collection)
    )
    return
        $collection
};

declare function deploy:package($collection as xs:string, $expathConf as element()) {
    let $name := concat($expathConf/@abbrev, "-", $expathConf/@version, ".xar")
    let $xar := compression:zip(xs:anyURI($collection), true(), $collection)
    return
        xmldb:store("/db/system/repo", $name, $xar, "application/zip")
};

declare function deploy:deploy($collection as xs:string, $expathConf as element()) {
    let $pkg := deploy:package($collection, $expathConf)
    let $null := (
        xmldb:remove($collection)
    )
    return
        repo:install-and-deploy-from-db($pkg)
};

declare function deploy:update-or-create($json as map(*)) {
    let $existing := repo:get-resource($json?uri, "expath-pkg.xml")
    let $user := deploy:check-user($json)
    return
        if (exists($existing)) then
            "found app"
        else
            try {
                let $mkcol := deploy:mkcol("/db/system/repo", (), ())
                let $target := deploy:create-app("/db/system/repo/" || $json?abbrev, $json)
                return
                    deploy:deploy($target, doc($target || "/expath-pkg.xml")/*)
            } catch * {
                map {
                    "result": "error",
                    "message": ($err:description, $err:value, $err:additional)[1]
                }
            }
};

let $data := request:get-data()
let $json := parse-json(util:binary-to-string($data))
return
    deploy:update-or-create($json)