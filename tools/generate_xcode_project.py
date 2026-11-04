#!/usr/bin/env python3
"""Generate the Frit app project. The chemistry library stays a local Swift package."""
from pathlib import Path
import hashlib
import json
import plistlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'Frit.xcodeproj'

def oid(name):
    return hashlib.sha256(('Frit-Xcode/' + name).encode()).hexdigest()[:24].upper()

objects = {}
def obj(identity, isa, **fields):
    key = oid(identity)
    objects[key] = {'isa': isa, **fields}
    return key

def encode(value, depth=0):
    pad = '\t' * depth
    if isinstance(value, dict):
        return '{\n' + ''.join('\t' * (depth+1) + json.dumps(k) + ' = ' + encode(v, depth+1) + ';\n' for k,v in value.items()) + pad + '}'
    if isinstance(value, list):
        return '(\n' + ''.join('\t' * (depth+1) + encode(v, depth+1) + ',\n' for v in value) + pad + ')'
    if isinstance(value, int):
        return str(value)
    return json.dumps(value, ensure_ascii=False)

sources = []
source_refs = []
for path in sorted((ROOT/'Sources/GlazeApp').glob('*.swift')):
    rel = path.relative_to(ROOT).as_posix()
    ref = obj('file/'+rel, 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=rel, sourceTree='<group>')
    source_refs.append(ref)
    sources.append(obj('build/'+rel, 'PBXBuildFile', fileRef=ref))

resource_refs=[]
resource_build=[]
for rel,typ in [('Support/Assets.xcassets','folder.assetcatalog'), ('Support/PrivacyInfo.xcprivacy','text.xml')]:
    ref=obj('file/'+rel,'PBXFileReference',lastKnownFileType=typ,path=rel,sourceTree='<group>')
    resource_refs.append(ref)
    resource_build.append(obj('build/'+rel,'PBXBuildFile',fileRef=ref))
for rel,typ in [('Support/Xcode-Info.plist','text.plist.xml'),('Support/App.entitlements','text.plist.entitlements')]:
    resource_refs.append(obj('file/'+rel,'PBXFileReference',lastKnownFileType=typ,path=rel,sourceTree='<group>'))

pkg = obj('local-package', 'XCLocalSwiftPackageReference', relativePath='.')
core = obj('core-product', 'XCSwiftPackageProductDependency', package=pkg, productName='GlazeCore')
core_build = obj('core-build', 'PBXBuildFile', productRef=core)
app = obj('app-product','PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='Frit.app',sourceTree='BUILT_PRODUCTS_DIR')
source_group=obj('source-group','PBXGroup',children=source_refs,name='App sources',sourceTree='<group>')
support_group=obj('support-group','PBXGroup',children=resource_refs,name='Support',sourceTree='<group>')
products=obj('product-group','PBXGroup',children=[app],name='Products',sourceTree='<group>')
main_group=obj('main-group','PBXGroup',children=[source_group,support_group,products],sourceTree='<group>')
src_phase=obj('sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=sources,runOnlyForDeploymentPostprocessing=0)
res_phase=obj('resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=resource_build,runOnlyForDeploymentPostprocessing=0)
frameworks=obj('frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[core_build],runOnlyForDeploymentPostprocessing=0)

project_configs=[]
target_configs=[]
for name in ['Debug','Release']:
    config={'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','MACOSX_DEPLOYMENT_TARGET':'14.0','SDKROOT':'macosx','SWIFT_VERSION':'6.0','CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':'55R57JNHZX'}
    config.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG $(inherited)','DEBUG_INFORMATION_FORMAT':'dwarf','ONLY_ACTIVE_ARCH':'YES'} if name=='Debug' else {'SWIFT_COMPILATION_MODE':'wholemodule','SWIFT_OPTIMIZATION_LEVEL':'-O','DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym','ONLY_ACTIVE_ARCH':'NO','ENABLE_NS_ASSERTIONS':'NO'})
    project_configs.append(obj('project-config/'+name,'XCBuildConfiguration',buildSettings=config,name=name))
    target={'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','CODE_SIGN_ENTITLEMENTS':'Support/App.entitlements','COMBINE_HIDPI_IMAGES':'YES','CURRENT_PROJECT_VERSION':'6','ENABLE_APP_SANDBOX':'YES','ENABLE_HARDENED_RUNTIME':'YES','GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'Support/Xcode-Info.plist','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks'],'MARKETING_VERSION':'1.3.1','PRODUCT_BUNDLE_IDENTIFIER':'com.michaellip.frit','PRODUCT_NAME':'Frit','SKIP_INSTALL':'NO','SUPPORTED_PLATFORMS':'macosx'}
    target_configs.append(obj('target-config/'+name,'XCBuildConfiguration',buildSettings=target,name=name))
project_config_list=obj('project-config-list','XCConfigurationList',buildConfigurations=project_configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
target_config_list=obj('target-config-list','XCConfigurationList',buildConfigurations=target_configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
target=obj('app-target','PBXNativeTarget',buildConfigurationList=target_config_list,buildPhases=[src_phase,frameworks,res_phase],buildRules=[],dependencies=[],name='Frit',packageProductDependencies=[core],productName='Frit',productReference=app,productType='com.apple.product-type.application')
project=obj('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','TargetAttributes':{target:{'ProvisioningStyle':'Automatic'}}},buildConfigurationList=project_config_list,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main_group,packageReferences=[pkg],productRefGroup=products,projectDirPath='',projectRoot='',targets=[target])
PROJECT.mkdir(exist_ok=True)
payload={'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project}
(PROJECT/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode(payload)+'\n')

info=plistlib.loads((ROOT/'Support/GlazeApp-DocumentTypes.plist').read_bytes())
info.update({'CFBundleDevelopmentRegion':'$(DEVELOPMENT_LANGUAGE)','CFBundleDisplayName':'Frit','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','ITSAppUsesNonExemptEncryption':False,'LSApplicationCategoryType':'public.app-category.education','LSMinimumSystemVersion':'$(MACOSX_DEPLOYMENT_TARGET)','NSHighResolutionCapable':True,'NSHumanReadableCopyright':'Copyright © 2026 Michael Lip. All rights reserved.','NSPrincipalClass':'NSApplication','NSSupportsSuddenTermination':False})
(ROOT/'Support/Xcode-Info.plist').write_bytes(plistlib.dumps(info,sort_keys=True))

scheme=ET.Element('Scheme',{'version':'1.7'})
act=ET.SubElement(scheme,'BuildAction',{'parallelizeBuildables':'YES','buildImplicitDependencies':'YES'})
entries=ET.SubElement(act,'BuildActionEntries')
entry=ET.SubElement(entries,'BuildActionEntry',{'buildForTesting':'YES','buildForRunning':'YES','buildForProfiling':'YES','buildForArchiving':'YES','buildForAnalyzing':'YES'})
def reference(parent):
    ET.SubElement(parent,'BuildableReference',{'BuildableIdentifier':'primary','BlueprintIdentifier':target,'BuildableName':'Frit.app','BlueprintName':'Frit','ReferencedContainer':'container:Frit.xcodeproj'})
reference(entry)
launch=ET.SubElement(scheme,'LaunchAction',{'buildConfiguration':'Debug','selectedDebuggerIdentifier':'Xcode.DebuggerFoundation.Debugger.LLDB','selectedLauncherIdentifier':'Xcode.IDEFoundation.Launcher.LLDB','launchStyle':'0','useCustomWorkingDirectory':'NO','ignoresPersistentStateOnLaunch':'NO','debugDocumentVersioning':'YES','debugServiceExtension':'internal','allowLocationSimulation':'YES'})
reference(ET.SubElement(launch,'BuildableProductRunnable',{'runnableDebuggingMode':'0'}))
profile=ET.SubElement(scheme,'ProfileAction',{'buildConfiguration':'Release','shouldUseLaunchSchemeArgsEnv':'YES','savedToolIdentifier':'','useCustomWorkingDirectory':'NO','debugDocumentVersioning':'YES'})
reference(ET.SubElement(profile,'BuildableProductRunnable',{'runnableDebuggingMode':'0'}))
ET.SubElement(scheme,'AnalyzeAction',{'buildConfiguration':'Debug'})
ET.SubElement(scheme,'ArchiveAction',{'buildConfiguration':'Release','revealArchiveInOrganizer':'YES'})
shared=PROJECT/'xcshareddata/xcschemes'
shared.mkdir(parents=True,exist_ok=True)
ET.indent(scheme)
ET.ElementTree(scheme).write(shared/'Frit.xcscheme',encoding='utf-8',xml_declaration=True)
print(f'Generated {PROJECT} with {len(sources)} app sources and local GlazeCore product.')
