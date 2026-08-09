# jac/ai-walkers/ai_walker_together.jac
# Ported from the ai-chat-network prototype's mtllm-era Jac to current
# jaclang + byllm syntax. The original was the most elaborate of the
# per-provider walkers (entry/exit node lifecycle, typed edges into a
# dedicated exit node) but didn't compile even under the old grammar (an
# undefined `Conversation` return-type annotation, a walker ability
# referencing an edge with a self-mutating `can` that the language treats
# as a no-op). This port keeps the original's *shape* -- a bounded
# conversation that walks into a dedicated farewell node after a turn
# limit, connected by a typed edge -- rather than an unbounded loop like
# the other provider walkers.

import from byllm.lib { Model }

glob together_llm: Model = Model(model_name="together_ai/meta-llama/Llama-3.3-70B-Instruct-Turbo");

def generate_response(conversation: str) -> str by together_llm();
sem generate_response = "Continue the conversation as a helpful assistant.";
sem generate_response.conversation = "The conversation so far, oldest turn first.";

obj AgentTogether {
    has name: str,
        introduction: str;

    def postinit {
        self.name = self.name.lower();
        self.introduction = self.introduction.lower();
    }
}

node Conversation {
    has context: str = "";
    has turns: int = 0;
}

node Farewell {}

edge Ends: Conversation --> Farewell {
    has reason: str = "max turns reached";
}

walker chat_together {
    has agent: AgentTogether;
    has max_turns: int = 3;

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
        here.turns += 1;
        if here.turns >= self.max_turns {
            visit [-->[?:Farewell]] else {
                bye = Farewell();
                here +>:Ends(reason="max turns reached"):+> bye;
                visit bye;
            }
        } else {
            visit here;
        }
    }

    can farewell with Farewell entry {
        print(f"{self.agent.name}: it's been good talking with you. Goodbye.");
        disengage;
    }
}

with entry:__main__ {
    agent = AgentTogether(name="Together", introduction="Hello, I am AI Agent Together.");
    root spawn chat_together(agent=agent);
}
