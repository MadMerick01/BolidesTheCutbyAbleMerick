angular.module('beamng.apps')
  .directive('bolideTheCutBootstrap', function () {
    return {
      restrict: 'E',
      replace: true,

      // IMPORTANT: inline template = no templateUrl = no 404 ever
      // Keep this app invisible to avoid blocking or cluttering the GUI.
      template: '<div class="bolide-bootstrap-app" style="display:none;"></div>',

      controller: function ($scope, $element) {
        if (window.bngApi && bngApi.engineLua) {
          bngApi.engineLua(
            'if extensions and extensions.load then ' +
              'if not (extensions.isExtensionLoaded and extensions.isExtensionLoaded("bolidesTheCut")) then ' +
                'extensions.load("bolidesTheCut");' +
              'end;' +
              'if extensions.bolidesTheCut and extensions.bolidesTheCut.setWindowVisible then ' +
                'extensions.bolidesTheCut.setWindowVisible(true);' +
              'end;' +
            'end'
          );
        }
      }
    };
  });
