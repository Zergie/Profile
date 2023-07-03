[cmdletbinding()]
param(
    [Parameter(Mandatory = $true,
               Position = 0,
               ParameterSetName="PathParameterSet")]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string]
    $Path
)
$ErrorActionPreference = 'Stop'

Add-Type @"
    using System;
    using System.Collections.Generic;
    using System.IO;
    using System.Runtime.InteropServices;
    using System.Runtime.InteropServices.ComTypes;

    public class Helper
    {
        [DllImport("oleaut32.dll", PreserveSig = false)]
        public static extern ITypeLib LoadTypeLib([In, MarshalAs(UnmanagedType.LPWStr)] string typelib);

        public class ComClass
        {
            public string clsid { get; set; }
            public string tlbid { get; set; }
            public string description { get; set; }
            public string progid { get; set; }
        }
        public class ComInterfaceExternalProxyStub
        {
            public string name { get; set; }
            public string iid { get; set; }
            public string tlbid { get; set; }
            public string proxyStubClsid32 { get; set; }
        }


        public static IEnumerable<object> ParseTypeLib(string filePath)
        {
            var fileNameOnly = Path.GetFileNameWithoutExtension(filePath);
            var typeLib = LoadTypeLib(filePath);

            var count = typeLib.GetTypeInfoCount();
            var ipLibAtt = IntPtr.Zero;
            typeLib.GetLibAttr(out ipLibAtt);

            var typeLibAttr = (System.Runtime.InteropServices.ComTypes.TYPELIBATTR)
                Marshal.PtrToStructure(ipLibAtt, typeof(System.Runtime.InteropServices.ComTypes.TYPELIBATTR));
            var tlbId = typeLibAttr.guid;

            for(var i=0; i< count; i++)
            {
                ITypeInfo typeInfo = null;
                typeLib.GetTypeInfo(i, out typeInfo);

                //figure out what guids, typekind, and names of the thing we're dealing with
                var ipTypeAttr = IntPtr.Zero;
                typeInfo.GetTypeAttr(out ipTypeAttr);
                var typeattr = (System.Runtime.InteropServices.ComTypes.TYPEATTR)
                    Marshal.PtrToStructure(ipTypeAttr, typeof(System.Runtime.InteropServices.ComTypes.TYPEATTR));

                var typeKind = typeattr.typekind;
                var typeId = typeattr.guid;

                //get the name of the type
                string strName, strDocString, strHelpFile;
                int dwHelpContext;
                typeLib.GetDocumentation(i, out strName, out strDocString, out dwHelpContext, out strHelpFile);


                // yield return new {
                //     name = strName,
                //     docString = strDocString,
                //     kind = typeKind,
                // };
                // yield return typeattr;

                if (typeattr.typekind == System.Runtime.InteropServices.ComTypes.TYPEKIND.TKIND_DISPATCH)
                {
                    yield return $"{strName}";
                    //yield return typeattr;

                    for(var j=0; j<typeattr.cFuncs; j++)
                    {
                        var ipFuncDesc = IntPtr.Zero;
                        typeInfo.GetFuncDesc(j, out ipFuncDesc);
                        var funcdesc = (System.Runtime.InteropServices.ComTypes.FUNCDESC)
                            Marshal.PtrToStructure(ipFuncDesc, typeof(System.Runtime.InteropServices.ComTypes.FUNCDESC));

                        typeInfo.GetDocumentation(funcdesc.memid, out strName, out strDocString, out dwHelpContext, out strHelpFile);
                        yield return $"   {strName}()";
                    }
                }

                // if (typeKind == System.Runtime.InteropServices.ComTypes.TYPEKIND.TKIND_COCLASS)
                // {
                //     yield return new ComClass
                //     {
                //         clsid = typeId.ToString("B").ToUpper(),
                //         tlbid = tlbId.ToString("B").ToUpper(),
                //         description = strDocString,
                //         progid = $"{fileNameOnly}.{strName}",
                //     };
                // }
                // else if(typeKind == System.Runtime.InteropServices.ComTypes.TYPEKIND.TKIND_INTERFACE)
                // {
                //     yield return new ComInterfaceExternalProxyStub
                //     {
                //         name = strName,
                //         iid = typeId.ToString("B").ToUpper(),
                //         tlbid = tlbId.ToString("B").ToUpper(),
                //         proxyStubClsid32 = "{00020424-0000-0000-C000-000000000046}",
                //     };
                // }
            }
        }
    }
"@

[Helper]::ParseTypeLib((Resolve-Path $Path).Path)
