# Model detection sources

Checked 2026-10-13. The catalog recognizes explicit publisher IDs, vendor-prefixed
IDs, dated snapshots, and standard OpenRouter routing suffixes. Unknown family
members keep manual settings. Detection does not guarantee account access or
that a gateway implements every native model feature.

| Publisher | Added presets | Official source |
| --- | --- | --- |
| OpenAI | GPT Image 2, GPT Image 2.5 Sunburst/Flare, ChatGPT Image Latest; GPT-5.5 | [Image API models](https://developers.openai.com/api/reference/resources/images/methods/generate), [GPT-5.5](https://developers.openai.com/api/docs/models/gpt-5.5) |
| Google | Gemini 2.5 Pro/Flash/Flash-Lite; 3 Flash and 3.1 Pro previews; 3.1/3.5 Flash-Lite; 3.8 Flash; Gemini image models including Nano Banana 2.1 | [Model directory](https://ai.google.dev/gemini-api/docs/models), [2.5 Flash](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash), [2.5 image](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash-image), [3.1 image](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-image), [Nano Banana 2.1](https://ai.google.dev/gemini-api/docs/models/gemini-nano-banana-2.1), [image Lite](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-lite-image) |
| Alibaba | Qwen 3.5 Plus/Flash, 3.6 Plus, 3.8 Max | [3.5 Plus](https://www.alibabacloud.com/help/en/model-studio/qwen3-5-plus), [3.5 Flash](https://www.alibabacloud.com/help/en/model-studio/qwen3-5-flash), [3.6 Plus](https://www.alibabacloud.com/help/en/model-studio/qwen3-6-plus), [3.8 Max](https://help.aliyun.com/en/model-studio/qwen3-8-max) |
| xAI | Grok 4.7; Grok Imagine Image 2.0 | [Grok 4.7](https://docs.x.ai/developers/models/grok-4.7), [image model](https://docs.x.ai/developers/models/grok-imagine-image-2.0), [edits](https://docs.x.ai/developers/model-capabilities/images/editing), [multiple references](https://docs.x.ai/developers/model-capabilities/images/multi-image-editing) |
| Mistral | Large 4, Medium 3.5, Small 4 | [Large 4](https://docs.mistral.ai/models/mistral-large-4-0), [Medium 3.5](https://docs.mistral.ai/models/mistral-medium-3-5-26-04), [Small 4](https://docs.mistral.ai/models/mistral-small-4-0-26-03), [reasoning](https://docs.mistral.ai/studio/conversations/reasoning) |
| Cohere | Command A+, A, A Reasoning, A Vision, R/R+/R7B dated variants | [Model limits and modalities](https://docs.cohere.com/v2/docs/models) |

Grok and Mistral chat entries use an 8,192-token output default because their
referenced model pages publish context windows without a separate output cap.
This is an app default, not a claimed provider maximum. Image API entries keep
the existing token fields as editor fallbacks; those APIs do not use chat token
budgets.

Gemini image presets select chat image output for compatible gateways such as
OpenRouter. Google's native `generateContent` image API is not the OpenAI chat
protocol; a native Google image endpoint needs a gateway. Google's text models
can use its [OpenAI-compatible chat endpoint](https://ai.google.dev/gemini-api/docs/openai).
Cohere presets likewise describe capabilities for compatible deployments;
they do not add Cohere's native Chat API protocol.
Command A Vision has image input but [does not support tool use](https://docs.cohere.com/v2/docs/command-a-vision).

For `api.x.ai`, image edits use JSON image data URIs and accept up to five
references. Other Images API endpoints retain their multipart edit format.

## Reference-image inputs

Checked 2026-10-17 for all reference-capable image presets currently in Tako.
Reference support does not imply unlimited inputs or the same limit for every
model. The following defaults also apply to saved profiles that only stored the
older reference-input boolean.

| Model | Default reference count | Basis |
| --- | --- | --- |
| GPT Image 1, 1 Mini, 1.5, 2, 2.5 Sunburst/Flare; ChatGPT Image Latest | 16 | [OpenAI Images edit API](https://developers.openai.com/api/reference/python/resources/images/methods/edit) accepts up to 16 input files. |
| Gemini 2.5 Flash Image, including its preview alias | 3 | [Google image-generation guide](https://ai.google.dev/gemini-api/docs/image-generation#limitations) recommends up to 3 inputs for best results. This is a conservative app default, not a claimed hard API maximum. |
| Gemini 3 Pro Image, 3.1 Flash Image, Nano Banana 2.1, 3.1 Flash Lite Image, including catalog preview aliases | 14 | [Google reference-image guide](https://ai.google.dev/gemini-api/docs/image-generation#use_up_to_14_reference_images) allows up to 14; character, object and style fidelity have separate guidance. Lite is not optimized for multiple reference inputs. |
| Grok Imagine Image 2.0 | 5 | [xAI Imagine overview](https://docs.x.ai/developers/model-capabilities/imagine) documents up to 5 source images. |
| Image Playground | 1 | The current Tako ImageCreator integration accepts at most one image; this is also enforced by its platform adapter. |
| Other manually configured image models, including Responses image tools | 1 | Unknown limits are not inferred from vision support or an API format. Set the provider's supported count in model settings. |

The reference switch remains the opt-in: turning it off accepts zero references.
An explicit per-model count overrides presets for compatible gateways; the app
still bounds a request to 16 references, xAI's direct Images transport to 5, and
the current on-device integration to 1. A lower provider limit can be configured
without disabling multiple-image support elsewhere. Discovery preserves edited
model settings.

`generate_image` counts attachments and ordered workspace paths together. With
automatic model selection it skips candidates that cannot accept the full count;
with an explicit model it returns a stable error and the candidate limits before
reading paths or opening a provider request. No images are silently dropped or
split into independent generations. Direct image requests reject excess draft
attachments before creating a message, and transports enforce the same policy.
The chat composer's separate limit of 8 total attachments remains in place;
workspace paths let the tool use higher model limits.
