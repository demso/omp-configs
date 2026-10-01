import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";

const PROVIDER = "surplus-images";
const IMAGE_MODEL_IDS: Record<string, true> = {
	"venice-z-image-turbo": true,
	"venice-qwen-image-2": true,
	"grok-imagine-edit": true,
	"gpt-image-2-edit": true,
	"venice-chroma": true,
	"firered-image-edit": true,
	"venice-wai-illustrious": true
};

function markRegisteredModelsAsImages(ctx: ExtensionContext): void {
	for (const model of ctx.modelRegistry.getAll("all")) {
		if (model.provider === PROVIDER && IMAGE_MODEL_IDS[model.id]) {
			model.kind = "image";
		}
	}
}

export default function surplusImagesExtension(pi: ExtensionAPI): void {
	pi.registerProvider(PROVIDER, {
		baseUrl: "https://api.surplusintelligence.ai/v1",
		apiKey: "SURPLUS_KEY",
		api: "openai-images",
		models: [
			{
				id: "venice-z-image-turbo",
				name: "Z-Image Turbo (Surplus)",
				reasoning: false,
				input: ["text"],
				contextWindow: 1,
				maxTokens: 1,
			},
			{
				id: "venice-chroma",
				name: "Chroma (Surplus)",
				reasoning: false,
				input: ["text"],
				contextWindow: 1,
				maxTokens: 1,
			},
			{
				id: "venice-qwen-image-2",
				name: "Qwen Image 2 (Surplus)",
				reasoning: false,
				input: ["text"],
				contextWindow: 1,
				maxTokens: 1,
			},
			{
				id: "venice-wai-illustrious",
				name: "Wai Illustrious (Surplus)",
				reasoning: false,
				input: ["text"],
				contextWindow: 1,
				maxTokens: 1,
			},
			{
				id: "grok-imagine-edit",
				name: "Grok Imagine Edit (Surplus)",
				reasoning: false,
				input: ["text", "image"],
				contextWindow: 1,
				maxTokens: 1,
			},
			{
				id: "gpt-image-2-edit",
				name: "GPT Image 2 Edit (Surplus)",
				reasoning: false,
				input: ["text", "image"],
				contextWindow: 1,
				maxTokens: 1,
			},
			{
				id: "firered-image-edit",
				name: "Firered Image Edit (Surplus)",
				reasoning: false,
				input: ["text", "image"],
				contextWindow: 1,
				maxTokens: 1,
			},
		],
	});

	// Provider registration currently has no public `kind` field. Mark only this
	// provider's explicitly registered models after pending registrations apply.
	pi.on("session_start", async (_event, ctx) => markRegisteredModelsAsImages(ctx));
	pi.on("before_agent_start", async (_event, ctx) => markRegisteredModelsAsImages(ctx));
}
