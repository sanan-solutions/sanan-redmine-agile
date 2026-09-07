# Chart rendering for sprint report (Chart.js).
# Expects window.SANAN_SPRINT_CHARTS = { commitActual, roles, members, completion }
(function () {
  function ready(fn) {
    if (document.readyState !== 'loading') fn();
    else document.addEventListener('DOMContentLoaded', fn);
  }

  var COLORS = {
    commit: 'rgba(54, 112, 180, 0.85)',
    actual: 'rgba(70, 150, 90, 0.85)',
    be: 'rgba(70, 130, 180, 0.85)',
    fe: 'rgba(230, 140, 50, 0.85)',
    qa: 'rgba(140, 100, 180, 0.85)',
    completion: 'rgba(200, 80, 80, 0.9)',
    members: [
      'rgba(54, 112, 180, 0.85)',
      'rgba(70, 150, 90, 0.85)',
      'rgba(230, 140, 50, 0.85)',
      'rgba(140, 100, 180, 0.85)',
      'rgba(200, 80, 80, 0.85)',
      'rgba(90, 160, 160, 0.85)',
      'rgba(160, 120, 80, 0.85)',
      'rgba(100, 100, 120, 0.85)'
    ]
  };

  function baseOptions(yTitle) {
    return {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { position: 'bottom' },
        tooltip: { mode: 'index', intersect: false }
      },
      scales: {
        x: { ticks: { maxRotation: 45, minRotation: 0 } },
        y: {
          beginAtZero: true,
          title: yTitle ? { display: true, text: yTitle } : undefined
        }
      }
    };
  }

  function makeChart(canvasId, config) {
    var el = document.getElementById(canvasId);
    if (!el || typeof Chart === 'undefined') return;
    return new Chart(el.getContext('2d'), config);
  }

  ready(function () {
    var data = window.SANAN_SPRINT_CHARTS;
    if (!data || typeof Chart === 'undefined') return;

    if (data.commitActual && data.commitActual.labels && data.commitActual.labels.length) {
      makeChart('sanan-chart-commit-actual', {
        type: 'bar',
        data: {
          labels: data.commitActual.labels,
          datasets: [
            {
              label: data.labels.commit,
              data: data.commitActual.commit,
              backgroundColor: COLORS.commit,
              borderRadius: 2
            },
            {
              label: data.labels.actual,
              data: data.commitActual.actual,
              backgroundColor: COLORS.actual,
              borderRadius: 2
            }
          ]
        },
        options: baseOptions(data.labels.sp)
      });
    }

    if (data.roles && data.roles.labels && data.roles.labels.length) {
      makeChart('sanan-chart-roles', {
        type: 'bar',
        data: {
          labels: data.roles.labels,
          datasets: [
            {
              label: data.labels.be,
              data: data.roles.be,
              backgroundColor: COLORS.be,
              borderRadius: 2
            },
            {
              label: data.labels.fe,
              data: data.roles.fe,
              backgroundColor: COLORS.fe,
              borderRadius: 2
            },
            {
              label: data.labels.qa,
              data: data.roles.qa,
              backgroundColor: COLORS.qa,
              borderRadius: 2
            }
          ]
        },
        options: baseOptions(data.labels.sp)
      });
    }

    if (data.completion && data.completion.labels && data.completion.labels.length) {
      makeChart('sanan-chart-completion', {
        type: 'line',
        data: {
          labels: data.completion.labels,
          datasets: [
            {
              label: data.labels.completion,
              data: data.completion.values,
              borderColor: COLORS.completion,
              backgroundColor: 'rgba(200, 80, 80, 0.12)',
              fill: true,
              tension: 0.25,
              spanGaps: true,
              pointRadius: 4
            }
          ]
        },
        options: (function () {
          var opts = baseOptions('%');
          opts.scales.y.max = Math.max(120, Math.ceil((data.completion.max || 100) / 10) * 10);
          return opts;
        })()
      });
    }

    if (data.members && data.members.labels && data.members.labels.length) {
      makeChart('sanan-chart-members', {
        type: 'doughnut',
        data: {
          labels: data.members.labels,
          datasets: [
            {
              data: data.members.values,
              backgroundColor: data.members.labels.map(function (_, i) {
                return COLORS.members[i % COLORS.members.length];
              })
            }
          ]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: { position: 'right' }
          }
        }
      });
    }
  });
})();
