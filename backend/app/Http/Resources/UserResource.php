<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class UserResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'phone' => $this->phone,
            'name' => $this->name,
            'business_name' => $this->business_name,
            'role' => $this->role,
            'language_code' => $this->language_code,
            'city' => $this->whenLoaded('city', fn () => $this->city ? [
                'id' => $this->city->id,
                'name' => $this->city->name,
                'country_id' => $this->city->country_id,
            ] : null),
            'needs_setup' => $this->city_id === null,
        ];
    }
}
