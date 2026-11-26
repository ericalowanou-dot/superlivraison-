<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class CallResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'order_id' => $this->order_id,
            'caller_id' => $this->caller_id,
            'callee_id' => $this->callee_id,
            'video' => $this->video,
            'status' => $this->status,
            'answered_at' => $this->answered_at,
            'ended_at' => $this->ended_at,
            'duration_seconds' => $this->durationSeconds(),
            'created_at' => $this->created_at,
        ];
    }
}
