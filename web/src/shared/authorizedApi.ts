type ApiError = { error?: { message?: string } };
type Envelope<T> = { data: T };

export async function authorizedRequest<T>(
  path: string,
  token: string,
  init: RequestInit = {},
): Promise<T> {
  const response = await fetch(path, {
    ...init,
    credentials: "same-origin",
    headers: { authorization: `Bearer ${token}`, ...init.headers },
  });
  const body = (await response.json()) as Envelope<T> & ApiError;

  if (!response.ok) {
    throw new Error(body.error?.message ?? "The request was rejected");
  }

  return body.data;
}
