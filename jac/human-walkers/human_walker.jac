# jac/human-walkers/human_walker.jac
# Ported from the ai-chat-network prototype's mtllm-era Jac to current
# jaclang + byllm syntax. The original referenced generate_together_response
# without defining or importing it in this file, and called `print(x = ...)`
# to both assign and print in one expression -- neither compiles under
# current jaclang, and the second wasn't valid Python either. This port is
# self-contained and drops the original's unused post-init step (username/
# email normalization) since it never fed into the conversation logic.

import from byllm.lib { Model }

glob human_sim_llm: Model = Model(model_name="together_ai/meta-llama/Llama-3.3-70B-Instruct-Turbo");

def generate_response(conversation: str) -> str by human_sim_llm();
sem generate_response = "Respond the way a thoughtful, engaged human participant would.";
sem generate_response.conversation = "The conversation so far, oldest turn first.";

obj HumanUserProfile {
    has username: str = "",
        email: str = "";
}

node Conversation {
    has context: str = "";
}

walker human_chat {
    has profile: HumanUserProfile;

    can start with Root entry {
        print(f"User: {self.profile.username}, Email: {self.profile.email}");
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
    profile = HumanUserProfile(username="explorer", email="explorer@example.com");
    root spawn human_chat(profile=profile);
}
