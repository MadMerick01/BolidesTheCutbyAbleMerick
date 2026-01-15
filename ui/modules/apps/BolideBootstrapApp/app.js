angular.module('beamng.apps')
  .directive('bolideTheCutBootstrap', function () {
    return {
      restrict: 'E',
      replace: true,

      // IMPORTANT: inline template = no templateUrl = no 404 ever
      template: '<div style="display:none"></div>',

      controller: function ($scope, $element) {
        $element.css({ display: 'none', width: '0px', height: '0px', opacity: 0 });

        if (window.bngApi && bngApi.engineLua) {
          bngApi.engineLua(
            'extensions.load("bolidesTheCut");' +
            'if extensions.bolidesTheCut and extensions.bolidesTheCut.setWindowVisible then ' +
              'extensions.bolidesTheCut.setWindowVisible(true);' +
            'end'
          );
        }
      }
    };
  });
