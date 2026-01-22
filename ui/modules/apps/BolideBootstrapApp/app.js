angular.module('beamng.apps')
  .directive('bolideTheCutBootstrap', function () {
    return {
      restrict: 'E',
      replace: true,

      // IMPORTANT: inline template = no templateUrl = no 404 ever
      template: [
        '<div class="bolide-bootstrap-app" ',
        'style="display:flex;align-items:center;justify-content:center;',
        'padding:8px;color:#e5e5e5;background:rgba(0,0,0,0.35);',
        'border-radius:4px;font-size:12px;text-align:center;">',
        '  <span>{{statusMessage}}</span>',
        '</div>'
      ].join(''),

      controller: function ($scope, $element) {
        $scope.statusMessage = 'Bootstrapping Bolides: The Cut...';
        $element.css({ minHeight: '32px' });

        if (window.bngApi && bngApi.engineLua) {
          bngApi.engineLua(
            'extensions.load("bolidesTheCut");' +
            'if extensions.bolidesTheCut and extensions.bolidesTheCut.setWindowVisible then ' +
              'extensions.bolidesTheCut.setWindowVisible(true);' +
            'end'
          );
          $scope.statusMessage = 'Bolides: The Cut loaded. If the window is hidden, toggle it in the UI.';
        } else {
          $scope.statusMessage = 'BeamNG API unavailable. Bolides: The Cut could not be loaded.';
        }
      }
    };
  });
