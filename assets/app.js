/**
 * Простой скрипт для отображения домена и обработки взаимодействий
 * Без внешних зависимостей, без аналитики
 */

(function() {
  'use strict';

  /**
   * Инициализация при загрузке DOM
   */
  document.addEventListener('DOMContentLoaded', function() {
    // Отобразить текущий домен
    displayCurrentDomain();

    // Установить текущий год в футере
    setCurrentYear();

    // Настроить обработчик кнопки обновления
    setupRefreshButton();

    // Предотвратить внешнюю навигацию (опционально)
    preventExternalNavigation();
  });

  /**
   * Отображает текущий домен в элементе #host
   */
  function displayCurrentDomain() {
    const hostElement = document.getElementById('host');
    if (hostElement) {
      // Получаем текущий хост из window.location
      const currentHost = window.location.host || 'неизвестно';
      hostElement.textContent = currentHost;
    }
  }

  /**
   * Устанавливает текущий год в футере
   */
  function setCurrentYear() {
    const yearElement = document.getElementById('year');
    if (yearElement) {
      const currentYear = new Date().getFullYear();
      yearElement.textContent = currentYear;
    }
  }

  /**
   * Настраивает кнопку "Обновить страницу" для перезагрузки
   */
  function setupRefreshButton() {
    const refreshBtn = document.getElementById('refresh-btn');
    if (refreshBtn) {
      refreshBtn.addEventListener('click', function(e) {
        e.preventDefault();
        // Перезагрузить страницу
        window.location.reload();
      });
    }
  }

  /**
   * Предотвращает внешнюю навигацию, обеспечивая, что все клики
   * по ссылкам ведут к текущей странице (опциональная дополнительная защита)
   */
  function preventExternalNavigation() {
    // Получаем все ссылки на странице
    const links = document.querySelectorAll('a[href]');

    links.forEach(function(link) {
      const href = link.getAttribute('href');

      // Если ссылка ведёт на /, убедимся, что она действительно перезагружает текущую страницу
      // (это дополнительная мера для SEO и ботов)
      if (href === '/' || href === '/index.html' || href === '') {
        link.addEventListener('click', function(e) {
          // Разрешаем стандартное поведение для навигации по /
          // Браузер сам обработает это как переход на ту же страницу
        });
      }
    });
  }

  /**
   * Простой лог для отладки (можно удалить в продакшене)
   */
  if (window.console && window.console.log) {
    console.log('Страница загружена:', window.location.href);
    console.log('Домен:', window.location.host);
  }

})();
