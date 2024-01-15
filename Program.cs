using Microsoft.Azure.Functions.Worker.Extensions.OpenApi.Extensions;
using Microsoft.Azure.WebJobs.Extensions.OpenApi.Core.Abstractions;
using Microsoft.Azure.WebJobs.Extensions.OpenApi.Core.Configurations;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.OpenApi.Models;
using System.Net;

namespace TestNSwagFunction
{
    public class Program
    {
        public static void Main()
        {
            var host = new HostBuilder()
                .ConfigureFunctionsWorkerDefaults(
                    builder =>
                    {
                        builder.UseMiddleware<ExceptionLoggingMiddleware>();
                        builder.UseNewtonsoftJson();
                    })
                    .ConfigureServices(services =>
                    {
                        services = ConfigureOpenApiOptions(services);
                    })
                .Build();

            host.Run();
        }

        private static IServiceCollection ConfigureOpenApiOptions(IServiceCollection serviceCollection)
        {
            return serviceCollection.AddSingleton<IOpenApiConfigurationOptions>(_ =>
             {
                 var options = new OpenApiConfigurationOptions()
                 {
                     Info = new OpenApiInfo()
                     {
                         Version = DefaultOpenApiConfigurationOptions.GetOpenApiDocVersion(),
                         Title = $"{DefaultOpenApiConfigurationOptions.GetOpenApiDocTitle()} (Injected)",
                         Description = DefaultOpenApiConfigurationOptions.GetOpenApiDocDescription(),
                         TermsOfService = new Uri("https://github.com/Azure/azure-functions-openapi-extension"),
                         Contact = new OpenApiContact()
                         {
                             Name = "Test",
                             Email = "test@localhost",
                             Url = new Uri("https://localhost"),
                         },
                         License = new OpenApiLicense()
                         {
                             Name = "MIT",
                             Url = new Uri("http://opensource.org/licenses/MIT"),
                         }
                     },
                     Servers = DefaultOpenApiConfigurationOptions.GetHostNames(),
                     OpenApiVersion = DefaultOpenApiConfigurationOptions.GetOpenApiVersion(),
                     IncludeRequestingHostName = DefaultOpenApiConfigurationOptions.IsFunctionsRuntimeEnvironmentDevelopment(),
                     ForceHttps = DefaultOpenApiConfigurationOptions.IsHttpsForced(),
                     ForceHttp = DefaultOpenApiConfigurationOptions.IsHttpForced(),
                 };

                 return options;
             })
            .AddSingleton<IOpenApiHttpTriggerAuthorization>(_ =>
            {
                var auth = new OpenApiHttpTriggerAuthorization(req =>
                {
                    var result = new OpenApiAuthorizationResult()
                    {
                        StatusCode = HttpStatusCode.NotFound,
                        ContentType = "text/plain",
                        Payload = string.Empty,
                    };

                    if (DefaultOpenApiConfigurationOptions.IsFunctionsRuntimeEnvironmentDevelopment())
                    {
                        return Task.FromResult(default(OpenApiAuthorizationResult));
                    }

                    return Task.FromResult(result);
                });

                return auth;
            });
        }
    }
}