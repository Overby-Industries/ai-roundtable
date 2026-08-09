# jac/ai-walkers/ai_walker_openai.jac
# Ported from the ai-chat-network prototype's mtllm-era Jac to current
# jaclang + byllm syntax. Preserves the original's distinct shape (a named
# `AgentOpenAI` obj with post-init normalization) rather than the generic
# multi_model_chat.jac copy used for the anthropic/groq/huggingface/ollama
# walkers -- this file and ai_walker_together.jac were written differently
# in the original prototype, so the port keeps that difference rather than
# flattening everything to one template.

import from byllm.lib { Model }

glob openai_llm: Model = Model(model_name="gpt-4o-mini");

def generate_response(conversation: str) -> str by openai_llm();
sem generate_response = "Continue the conversation as a helpful assistant.";
sem generate_response.conversation = "The conversation so far, oldest turn first.";

obj AgentOpenAI {
    has name: str,
        introduction: str;

    def postinit {
        self.name = self.name.lower();
        self.introduction = self.introduction.lower();
    }
}

node Conversation {
    has context: str = "";
}

walker chat_openai {
    has agent: AgentOpenAI;

    can start with Root entry {
        print(self.agent.introduction);
        visit [-->[?:Conversation]] else {
            fresh = here ++> Conversation();
            visit fresh;
        }
    }

    can converse with Conversation entry {
        user_message: str = input("User: ");
        here.context += "User: " + user_message + "\n";
        ai_response: str = generate_response(here.context);
        print(f"{self.agent.name}: {ai_response}");
        here.context += f"{self.agent.name}: {ai_response}\n";
        visit here;
    }
}

with entry:__main__ {
    agent = AgentOpenAI(name="OpenAI", introduction="Hello, I am AI Agent OpenAI.");
    root spawn chat_openai(agent=agent);
}
