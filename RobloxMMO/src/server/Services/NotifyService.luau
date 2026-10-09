--!strict
-- 플레이어 화면에 짧은 알림을 띄운다 ("가방이 가득 찼어요" 같은 안내).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

export type Kind = "good" | "bad" | "info"

local NotifyService = {}

-- 플레이어에게 알림 하나를 보낸다
function NotifyService.send(player: Player, message: string, kind: Kind?)
	Remotes.get(Remotes.Names.Notify):FireClient(player, message, kind or "info")
end

return NotifyService
