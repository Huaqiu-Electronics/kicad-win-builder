archs = ['x86', 'x64']
build_type = 'Release'

def do_init(list) {
    list.each { item ->
      powershell "Write-Host Doing init for ${item}"
      powershell ".\\build.ps1 -Init"
      powershell ".\\build.ps1 -Vcpkg -Latest -Arch ${item}"
    }
}

def do_build(list) {
    powershell "Write-Host NICK DBEUG Removing .out"
    powershell "Remove-Item .out -Recurse -ErrorAction SilentlyContinue"
    list.each { item ->
      powershell "Write-Host Doing build for ${item} ${build_type}"
      powershell ".\\build.ps1 -Build -Latest -Arch ${item} -BuildType ${build_type}"
    }
}

def do_package(list) {
    list.each { item ->
      powershell "Write-Host Doing package for ${item} ${build_type}"
      if (params.LITE_PKG_ONLY != true) {
        powershell "Write-Host Building full packge, be patient!"
        powershell ".\\build.ps1 -Package -Arch ${item} -BuildType ${build_type}"
      }
      powershell ".\\build.ps1 -Package -Arch ${item} -BuildType ${build_type} -Lite"
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
                do_build(archs)
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
                        do_package(archs)
                      }
                      dir (".out") {
                        stash includes: 'kicad*exe', name: 'installer_exe'
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
%SIGNTOOL% sign /as /n "Simon Richter" /fd sha256 /tr http://timestamp.digicert.com /td sha256 /v kicad-*exe
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
              sh "s3cmd put kicad-*.exe s3://kicad-downloads/windows/testing/"
          }
      }

    }
}
