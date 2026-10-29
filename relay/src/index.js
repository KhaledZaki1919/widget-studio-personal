import { handle } from "./relay.js";

export default {
  fetch(request, env, ctx) {
    return handle(request, env, ctx);
  },
};
