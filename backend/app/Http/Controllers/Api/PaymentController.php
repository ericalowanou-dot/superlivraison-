<?php

namespace App\Http\Controllers\Api;

use App\Contracts\PaymentGateway;
use App\Enums\PaymentMethod;
use App\Enums\PaymentStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\PaymentResource;
use App\Models\Order;
use App\Models\Payment;
use App\Services\PaymentService;
use App\Support\Phone;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class PaymentController extends Controller
{
    public function __construct(private PaymentService $payments) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        return PaymentResource::collection(
            Payment::with('order')->where('user_id', $request->user()->id)->latest('id')->paginate(20)
        );
    }

    public function store(Request $request, Order $order): JsonResponse
    {
        Gate::authorize('respond', $order);

        $data = $request->validate([
            'method' => ['required', Rule::enum(PaymentMethod::class)->except(PaymentMethod::Cash)],
            'phone' => ['required', 'string', 'max:30'],
        ]);
        $phone = Phone::normalize($data['phone'])
            ?? throw ValidationException::withMessages(['phone' => 'Ce numéro de téléphone est invalide.']);

        $payment = $this->payments->startMobile($order, $request->user(), PaymentMethod::from($data['method']), $phone);

        return (new PaymentResource($payment->load('order')))->response()->setStatusCode(201);
    }

    public function show(Payment $payment): PaymentResource
    {
        Gate::authorize('view', $payment);

        return new PaymentResource($payment->load('order'));
    }

    public function receipt(Payment $payment): Response
    {
        Gate::authorize('view', $payment);
        abort_unless(in_array($payment->status, [PaymentStatus::Succeeded, PaymentStatus::Refunded], true), 409, 'Aucun reçu pour ce paiement.');

        return Pdf::loadView('pdf.receipt', ['payment' => $payment->load('order', 'user')])
            ->download('recu-'.$payment->order->reference.'.pdf');
    }

    /** Appelé par l'agrégateur : seul ce résultat signé confirme un paiement. */
    public function webhook(Request $request, string $provider, PaymentGateway $gateway): JsonResponse
    {
        abort_unless($provider === $gateway->name(), 404);

        $event = $gateway->parseWebhook($request);
        abort_if($event === null, 401);

        $this->payments->applyWebhook($event);

        return response()->json(['received' => true]);
    }
}
