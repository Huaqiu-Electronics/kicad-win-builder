build_type = 'Release'
archs_to_build = []
archs_to_pack = []

def do_init(list) {
    powershell ".\\build.ps1 -Init"
    list.each { item ->
      powershell "Write-Host Doing init for ${item}"
      try {
        powershell ".\\build.ps1 -Vcpkg -Latest -Arch ${item}"
        archs_to_build.add( item )
      } catch (err) {
        currentBuild.result='UNSTABLE'
        echo 'Exception occurred: ' + err.toString()
        powershell "Write-Host 'Failed vcpkg for ${item}' -ForegroundColor Red"
      }
    }

    if( archs_to_build.size() == 0 )
    {
      currentBuild.result='FAILURE'
    }
}

def do_build(arches) {
    powershell "Write-Host NICK DBEUG Removing .out"
    powershell "Get-ChildItem .out -Exclude '*-pdb' | Remove-Item -Recurse -ErrorAction SilentlyContinue"
    
    arches.each { arch ->
      powershell "Write-Host Doing build for ${arch} ${build_type}"
      try {
        if(params.TRAIN != 'nightly') {
          powershell ".\\build.ps1 -Build -Arch ${arch} -BuildConfigName ${params.BUILD_CONFIG}"
        }
        else {
          powershell ".\\build.ps1 -Build -Latest -Arch ${arch} -BuildType ${build_type}"
        }
        archs_to_pack.add( arch )
      } catch (err) {
        currentBuild.result='UNSTABLE'
        echo 'Exception occurred: ' + err.toString()
        powershell "Write-Host 'Failed build for ${arch} ${build_type}' -ForegroundColor Red"
      }
    }
    
    if( archs_to_pack.size() == 0 )
    {
      currentBuild.result='FAILURE'
    }
}

def do_package(arches, lite) {
    arches.each { arch ->
      powershell "Write-Host Doing package for ${arch} ${build_type}"

      withCredentials([azureServicePrincipal('kicad-azuresigntool')]) {
        try {
          $signString = ' -Sign -SignAKV $True -AKVUrl "https://kicad-codesign.vault.azure.net/" -AKVTenantId $Env:AZURE_TENANT_ID -AKVAppId $Env:AZURE_CLIENT_ID -AKVAppSecret $Env:AZURE_CLIENT_SECRET -AKVCertName KiCadCodeSign'

          if( lite ) {
              powershell "Write-Host Building lite package"
              $cmd = ".\\build.ps1 -Package -Arch ${arch} -BuildConfigName ${params.BUILD_CONFIG} -Lite -Prepare \$True" + $signString
          } else {
              powershell "Write-Host Packaging full release"
              $cmd = ".\\build.ps1 -Package -Arch ${arch} -BuildConfigName ${params.BUILD_CONFIG} -DebugSymbols -Prepare \$True" + $signString
          }
          
          powershell  $cmd
        } catch (err) {
          currentBuild.result='UNSTABLE'
          echo 'Exception occurred: ' + err.toString()
          powershell "Write-Host 'Failed package for ${arch} ${build_type}' -ForegroundColor Red"
        }
      }

    }
}

pipeline {
    agent { label 'msvc' }
    options {
      timestamps ()
      skipDefaultCheckout true
    }
    environment {
        LC_ALL = 'C'
    }
    parameters {
        booleanParam(name: 'LITE_PKG_ONLY', defaultValue: false, description: 'Skip building the full installer')
        booleanParam(name: 'CLEAN_WS', defaultValue: false, description: 'Clean workspace')
        choice(name: 'TRAIN', choices: ['nightly', 'release', 'testing'], description: '')
        text(name: 'BUILD_CONFIG', defaultValue: '', description: 'kicad-nightly')
        text(name: 'TESTING_FOLDER', defaultValue: '', description: '')
        booleanParam(name: 'BUILD_X64', defaultValue: true, description: 'Build 64-bit')
        booleanParam(name: 'BUILD_X86', defaultValue: true, description: 'Build 32-bit')
    }


    stages {
      stage ('Checkout') {
          steps {
              script {
                if (params.CLEAN_WS == true) {
                  cleanWs()
                }
              }
              checkout([$class: 'GitSCM', branches: [[name: '*/akv']],
              doGenerateSubmoduleConfigurations: false,
              extensions: [],
              submoduleCfg: [],
              userRemoteConfigs: [[credentialsId: '',
              url: 'https://gitlab.com/kicad/packaging/kicad-win-builder.git']]])
          }
      }

      stage ('Init toolchain') {
          steps {
              script {
                archs = []

                if( params.BUILD_X64 ) {
                  archs.add( 'x64' )
                }

                if( params.BUILD_X86 ) {
                  archs.add( 'x86' )
                }

                do_init(archs)
              }
          }
      }

      stage ('Build KiCad') {
          steps {
              script {
                do_build(archs_to_build)
              }
          }
      }

      stage ('Package Lite') {
          when {
              expression {
                  return params.TRAIN == 'nightly';
              }
          }
          steps {
              script {
                do_package(archs_to_pack, true)
              }
              dir (".out") {
                archiveArtifacts allowEmptyArchive: false, artifacts: 'kicad*.exe', caseSensitive: true, defaultExcludes: true, fingerprint: true, onlyIfSuccessful: true
                bat "DEL /Q /F \"kicad*-lite.exe\"" 
              }
          }
      }

      stage ('Package Full') {
        steps {
            script {
              do_package(archs_to_pack, false)
            }
            dir (".out") {
              stash includes: 'kicad*-pdbs.zip', name: 'pdbs'
              
              archiveArtifacts allowEmptyArchive: false, artifacts: 'kicad*.exe', caseSensitive: true, defaultExcludes: true, fingerprint: true, onlyIfSuccessful: true
              archiveArtifacts allowEmptyArchive: false, artifacts: 'kicad*-pdbs.zip', caseSensitive: true, defaultExcludes: true, fingerprint: true, onlyIfSuccessful: true
              bat "DEL /Q /F \"kicad*.exe\"" 
              bat "DEL /Q /F \"kicad*.zip\"" 
            }
        }
      }
    }
}
