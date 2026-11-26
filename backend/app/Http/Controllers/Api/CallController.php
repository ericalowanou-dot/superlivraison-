<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\CallResource;
use App\Models\Call;
use App\Models\Order;
use App\Services\Calls;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

class CallController extends Controller
{
    public function __construct(private Calls $calls) {}

    /** Lance un appel : le téléphone de l'autre personne sonne. */
    public function store(Request $request, Order $order): JsonResponse
    {
        Gate::authorize('view', $order);
        $data = $request->validate(['video' => ['required', 'boolean']]);

        $call = $this->calls->start($request->user(), $order, (bool) $data['video']);

        return $this->withCredentials($request, $call, 201);
    }

    public function show(Request $request, Call $call): JsonResponse
    {
        $this->authorizeCall($request, $call);

        return response()->json(['call' => (new CallResource($this->calls->expireIfStale($call)))->resolve()]);
    }

    public function accept(Request $request, Call $call): JsonResponse
    {
        $this->authorizeCall($request, $call);

        return $this->withCredentials($request, $this->calls->accept($request->user(), $call));
    }

    /** Refuser, annuler ou raccrocher. */
    public function end(Request $request, Call $call): JsonResponse
    {
        $this->authorizeCall($request, $call);

        return response()->json(['call' => (new CallResource($this->calls->hangUp($request->user(), $call)))->resolve()]);
    }

    private function authorizeCall(Request $request, Call $call): void
    {
        abort_unless($call->involves($request->user()), 404);
    }

    private function withCredentials(Request $request, Call $call, int $status = 200): JsonResponse
    {
        $peer = $request->user()->id === $call->caller_id ? $call->callee : $call->caller;

        return response()->json([
            'call' => (new CallResource($call))->resolve(),
            'peer' => ['id' => $peer->id, 'name' => $peer->business_name ?? $peer->name],
            'zego' => $this->calls->credentials($request->user(), $call),
        ], $status);
    }
}
