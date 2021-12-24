archs = ['x64','x86']
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
        if(params.RELEASE) {
          powershell ".\\build.ps1 -Build -Arch ${arch} -ReleaseConfigName ${params.RELEASE_CONFIG}"
        }
        else {
          powershell ".\\build.ps1 -Build -Latest -Arch ${arch} -BuildType ${build_type}"
        }
        archs_to_pack.add( arch )
      } catch (err) {
        currentBuild.result='UNSTABLE'
        powershell "Write-Host 'Failed build for ${arch} ${build_type}' -ForegroundColor Red"
      }
    }
    
    if( archs_to_pack.size() == 0 )
    {
      currentBuild.result='FAILURE'
    }
}

def do_package(arches) {
    arches.each { arch ->
      powershell "Write-Host Doing package for ${arch} ${build_type}"
      try {
        if(params.RELEASE) {
            powershell "Write-Host Packaging full release"
            powershell ".\\build.ps1 -Package -Arch ${arch} -ReleaseConfigName ${params.RELEASE_CONFIG}"
        } else {
          if (params.LITE_PKG_ONLY != true) {
            powershell "Write-Host Building full package, be patient!"
            powershell ".\\build.ps1 -Package -Arch ${arch} -BuildType ${build_type} -DebugSymbols"
          }
          powershell ".\\build.ps1 -Package -Arch ${arch} -BuildType ${build_type} -Lite"
        }
      } catch (err) {
        currentBuild.result='UNSTABLE'
        powershell "Write-Host 'Failed package for ${arch} ${build_type}' -ForegroundColor Red"
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
        booleanParam(name: 'RELEASE', defaultValue: false, description: 'Build a release')
        text(name: 'RELEASE_CONFIG', defaultValue: '', description: '')
    }


    stages {
      stage ('Checkout') {
          steps {
              script {
                if (params.CLEAN_WS == true) {
                  cleanWs()
                }
              }
              checkout([$class: 'GitSCM', branches: [[name: '*/master']],
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

      stage('Package & Test') {
          parallel {
              stage ('Test KiCad') {
                  steps {
                      script {
                          dir (".build/kicad") {
                            powershell "dir"
                            //powershell "../../.support/cmake-3.16.6-win64-x64/bin/ctest python"
                            //powershell "../../.support/cmake-3.16.6-win64-x64/bin/ctest -T all"
                          }
                      }
                  }
              }
              stage ('Package KiCad') {
                  steps {
                      script {
                        do_package(archs_to_pack)
                      }
                      dir (".out") {
                        stash includes: 'kicad*exe', name: 'installer_exe'
                        stash includes: 'kicad*-pdbs.zip', name: 'pdbs'
                      }
                  }
              }
          }
      }

      stage ('Sign') {
          agent { label 'msys2' }
          steps {
              cleanWs()
              unstash 'installer_exe'
              bat "dir"
              bat """
set SIGNTOOL="C:\\Program Files (x86)\\Windows Kits\\10\\bin\\10.0.18362.0\\x86\\signtool.exe"
REM cd .out
dir
%SIGNTOOL% sign /a /a /n "KiCad Services Corporation" /fd sha256 /tr http://timestamp.sectigo.com /td sha256 /v kicad-*exe
 """
              stash includes: 'kicad*exe', name: 'signed_installer_exe'
          }
      }

      stage ('Archive') {
          agent { label 'master' }
          steps {

              cleanWs()
              unstash 'signed_installer_exe'
              sh "pwd"
              archiveArtifacts allowEmptyArchive: false, artifacts: 'kicad*.exe', caseSensitive: true, defaultExcludes: true, fingerprint: true, onlyIfSuccessful: true
              
              script {
                if (params.RELEASE == true) {
               //   sh "s3cmd put kicad-*.exe s3://kicad-downloads/windows/stable/"
                } else {
                  sh "s3cmd put kicad-*.exe s3://kicad-downloads/windows/nightly/"
                }
              }

              unstash 'pdbs'
              archiveArtifacts allowEmptyArchive: false, artifacts: 'kicad*-pdbs.zip', caseSensitive: true, defaultExcludes: true, fingerprint: true, onlyIfSuccessful: true
              
              script {
                if (params.RELEASE == true) {
                //  sh "s3cmd put kicad*-pdbs.zip s3://kicad-downloads/windows/stable/"
                } else {
                  sh "s3cmd put kicad*-pdbs.zip s3://kicad-downloads/windows/nightly/"
                }
              }
              
          }
      }

    }
}
