# jac/ai-walkers/ai_walker_ollama.jac
# Ported from the ai-chat-network prototype's mtllm-era Jac to current
# jaclang + byllm syntax. mtllm was renamed byllm upstream; the old
# `by ollama()` ability call, `` `?node `` traversal filters, and untyped
# `has` fields no longer parse under current jaclang (0.16.x). Ollama runs
# locally -- no API key needed, but the Ollama daemon must be running with
# the named model pulled (`ollama pull llama3`).

import from byllm.lib { Model }

glob ollama_llm: Model = Model(model_name="ollama/llama3");

def generate_response(conversation: str) -> str by ollama_llm();
sem generate_response = "Continue the conversation as a helpful assistant.";
sem generate_response.conversation = "The conversation so far, oldest turn first.";

node Conversation {
    has context: str = "";
}

walker chat_ollama {
    can start with Root entry {
        visit [-->[?:Conversation]] else {
            fresh = here ++> Conversation();
            visit fresh;
        }
    }

    can converse with Conversation entry {
        user_message: str = input("User: ");
        here.context += "User: " + user_message + "\n";
        ai_response: str = generate_response(here.context);
        print("AI: " + ai_response);
        here.context += "AI: " + ai_response + "\n";
        visit here;
    }
}

with entry:__main__ {
    root spawn chat_ollama();
}
