// hdrcap <hwnd> <out.f16>
//
// Captures one frame of a window through Windows.Graphics.Capture as
// R16G16B16A16_FLOAT: the composed picture in scRGB, as the display gets it,
// with no SDR conversion. A legacy (GDI) capture maps scRGB 1.0 to white and
// clips everything above it, so it cannot show HDR at all.
//
// Output: "F16 <width> <height>\n" followed by width*height*4 half floats
// (row-major, top row first).
#include <d3d11.h>
#include <dxgi.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>

#include <chrono>
#include <cstdio>
#include <thread>

using namespace winrt;
using namespace winrt::Windows::Graphics::Capture;
using namespace winrt::Windows::Graphics::DirectX;
using namespace winrt::Windows::Graphics::DirectX::Direct3D11;

int main(int argc, char** argv) {
  if (argc < 3) {
    std::fprintf(stderr, "usage: hdrcap <hwnd> <out.f16>\n");
    return 2;
  }
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  init_apartment(apartment_type::multi_threaded);
  HWND hwnd = reinterpret_cast<HWND>(static_cast<intptr_t>(_strtoi64(argv[1], nullptr, 0)));

  com_ptr<ID3D11Device> d3d;
  com_ptr<ID3D11DeviceContext> context;
  check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
                                  D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0,
                                  D3D11_SDK_VERSION, d3d.put(), nullptr,
                                  context.put()));
  auto dxgi = d3d.as<IDXGIDevice>();
  com_ptr<::IInspectable> inspectable;
  check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.get(), inspectable.put()));
  auto device = inspectable.as<IDirect3DDevice>();

  auto interop = get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
  GraphicsCaptureItem item{nullptr};
  check_hresult(interop->CreateForWindow(hwnd, guid_of<GraphicsCaptureItem>(),
                                         put_abi(item)));

  auto pool = Direct3D11CaptureFramePool::CreateFreeThreaded(
      device, DirectXPixelFormat::R16G16B16A16Float, 2, item.Size());
  auto session = pool.CreateCaptureSession(item);
  session.IsCursorCaptureEnabled(false);
  try {
    session.IsBorderRequired(false);
  } catch (...) {
  }
  session.StartCapture();

  Direct3D11CaptureFrame frame{nullptr};
  // Skip the first frames; the first one can predate the session settling.
  for (int got = 0, tries = 0; got < 3 && tries < 300; tries++) {
    auto next = pool.TryGetNextFrame();
    if (next) {
      frame = next;
      got++;
    } else {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
  }
  if (!frame) {
    std::fprintf(stderr, "no frame\n");
    return 1;
  }

  auto access = frame.Surface().as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
  com_ptr<ID3D11Texture2D> texture;
  check_hresult(access->GetInterface(guid_of<ID3D11Texture2D>(), texture.put_void()));
  D3D11_TEXTURE2D_DESC desc;
  texture->GetDesc(&desc);
  desc.Usage = D3D11_USAGE_STAGING;
  desc.BindFlags = 0;
  desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  desc.MiscFlags = 0;
  com_ptr<ID3D11Texture2D> staging;
  check_hresult(d3d->CreateTexture2D(&desc, nullptr, staging.put()));
  context->CopyResource(staging.get(), texture.get());
  D3D11_MAPPED_SUBRESOURCE mapped;
  check_hresult(context->Map(staging.get(), 0, D3D11_MAP_READ, 0, &mapped));

  FILE* out = nullptr;
  if (fopen_s(&out, argv[2], "wb") != 0) {
    return 1;
  }
  std::fprintf(out, "F16 %u %u\n", desc.Width, desc.Height);
  for (UINT y = 0; y < desc.Height; y++) {
    std::fwrite(static_cast<char*>(mapped.pData) + y * mapped.RowPitch, 8,
                desc.Width, out);
  }
  std::fclose(out);
  context->Unmap(staging.get(), 0);
  session.Close();
  pool.Close();
  std::printf("captured %ux%u\n", desc.Width, desc.Height);
  return 0;
}
