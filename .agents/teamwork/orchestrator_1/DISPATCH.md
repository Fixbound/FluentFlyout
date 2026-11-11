# Dispatch Log

## 2026-11-10T19:26:03Z

Sender: 6d839385-9970-4d36-ad60-8307714e7517
Content:
Retomar y perfeccionar la implementación de auto-actualización y CI en FluentFlyout (Camino A), asegurando que la aplicación empaquetada en MSIX verifique, descargue e instale releases desde el fork de GitHub con características premium desbloqueadas, respaldado por un workflow automatizado de GitHub Actions.

Working directory: E:\Programacion\FluentFlyout
Integrity mode: development

## Requirements

### R1. Configuración del Repositorio Objetivo para Actualizaciones
Configurar el endpoint de la API de GitHub en `UpdateCheckerService.cs` para consultar los releases del repositorio fork correspondiente, dejando la definición del destino (sea mediante configuración, detección de remote u otro mecanismo limpio) a criterio del equipo.

### R2. Robustecimiento del Auto-Updater en la Aplicación
Refinar `UpdateInstallerService.cs` y `UpdateCheckerService.cs` para asegurar que la verificación de versiones, descarga de `FluentFlyout_<version>_x64_Installer.zip`, validación de integridad por hash SHA-256, descompresión del paquete y ejecución desacoplada de `Add-AppDevPackage.ps1` gestionen errores limpiamente, no bloqueen la aplicación y generen logs claros.

### R3. Workflow de GitHub Actions para Construcción y Publicación MSIX
Ajustar y validar `.github/workflows/build-msix.yml` para compilar `FluentFlyoutMSIX.wapproj` bajo la configuración "GitHub Release" (x64), empaquetar el instalador zip junto con `SystemFiles/Add-AppDevPackage.ps1`, calcular el checksum SHA-256 en las notas del release y adjuntar el asset al release de GitHub.

### R4. Empaquetado y Compatibilidad de Instalación MSIX
Revisar `FluentFlyoutMSIX/Package.appxmanifest`, versionado y firma de prueba local para asegurar compatibilidad con las reglas de instalación de paquetes MSIX en Windows.

## Acceptance Criteria

### Compilación y Empaquetado
- [ ] `dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64` compila exitosamente con 0 errores y 0 warnings críticos.
- [ ] `FluentFlyoutMSIX.wapproj` genera el paquete MSIX y la estructura requerida para `FluentFlyout_<version>_x64_Installer.zip`.

### Updater y Verificación Local
- [ ] `UpdateCheckerService` parsea versiones y URLs de assets de GitHub Releases adecuadamente según la configuración definida.
- [ ] `UpdateInstallerService` valida estrictamente el checksum SHA-256 del archivo zip descargado antes de proceder a la extracción.
- [ ] La descompresión y el lanzamiento de `Add-AppDevPackage.ps1` se ejecutan en un proceso desacoplado, manejando escenarios de fallo con registro en logs.
- [ ] El flujo completo de verificación, descarga simulada, validación de hash y preparación de ejecución del instalador se valida localmente sin realizar commits ni pushes remotos.

### Workflow CI
- [ ] El archivo `.github/workflows/build-msix.yml` contiene sintaxis YAML válida y pasos reproducibles para la compilación x64 en "GitHub Release", cálculo de SHA-256 y publicación del asset en GitHub Releases.
