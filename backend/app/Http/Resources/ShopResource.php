<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ShopResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'category' => $this->category,
            'description' => $this->description,
            'phone' => $this->phone,
            'landmark' => $this->landmark,
            'lat' => $this->lat,
            'lng' => $this->lng,
            'has_image' => $this->image_path !== null,
        ];
    }
}
