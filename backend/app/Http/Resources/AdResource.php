<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class AdResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'category' => $this->category,
            'category_label' => $this->category->getLabel(),
            'title' => $this->title,
            'description' => $this->description,
            'status' => $this->status,
            'status_label' => $this->status->getLabel(),
            'rejection_reason' => $this->rejection_reason,
            'is_mine' => $this->user_id === $request->user()?->id,
            'created_at' => $this->created_at,
        ];
    }
}
