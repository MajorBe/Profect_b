extends Node
class_name EnemyConfig

# --- Базовые физические параметры движения ---
@export var walk_speed: float = 1.5       # скорость ходьбы
@export var run_speed: float = 2.0        # скорость бега 
@export var jump_speed: float = 4.3       # сила прыжка по Y (уменьшено с 8.0)
@export var gravity: float = 12.0         # ускорение падения
@export var max_fall_speed: float = 30.0  # ограничение максимальной скорости падения


# --- Дистанции для подхода/атаки ---
@export var approach_min: float = 0.2     # минимальная дистанция до игрока (раньше 1.5)
@export var approach_max: float = 0.35    # максимальная дистанция до игрока (раньше 3.5)
@export var attack_range: float = 0.4     # радиус атаки по X (раньше 2.0)

# --- Восстановления, уклонения, буферы ---
@export var post_hit_cooldown: float = 0.2        # время после получения удара, когда враг неактивен
@export var evade_iframes: float = 0.1            # время неуязвимости во время уклонения
@export var evade_cooldown: float = 1.0           # пауза между уклонениями
@export var end_buffer_sec: float = 0.3           # буфер в конце атаки (для комбо/очереди)
@export var feint_cooldown: float = 2.0           # пауза между «фейковыми» прыжками
@export var evade_chance_in_range: float = 0.08   # шанс увернуться при ближнем бое (раньше 0.35)

# --- Радиусы активации и забывания ---
@export var spawn_radius: float = 40.0   # радиус, в котором враг появляется (активируется)
@export var forget_radius: float = 80.0  # радиус, за пределами которого враг «забывает» игрока

# --- Дистанции и анимационные параметры ---
@export var hold_distance: float = -1.0   # если >= 0, враг всегда держит эту дистанцию от игрока
@export var anim_move_eps: float = 0.03   # порог скорости по X, после которого включается анимация ходьбы
@export var approach_side_offset: float = 0.0   # смещение по X (одинаковое влево и вправо)
@export var retreat_margin: float = 0.08        # гистерезис при отходе назад (чтобы не дёргался)

# --- Прыжки и «фейковые» прыжки ---
@export var jump_cooldown: float = 1.0        # минимальная пауза между прыжками
@export var feint_jump_chance: float = 0.05   # шанс обманного прыжка при подходе
@export var feint_jump_min: float = 1.0       # минимальная дистанция по X для фейкового прыжка
@export var feint_jump_max: float = 1.8       # максимальная дистанция по X для фейкового прыжка

# --- Хаотичное поведение (базовые значения) ---
@export_category("AI / Chaos (base)")
@export var chaos_pause_chance_base: float    = 0.02   # шанс «паузы» при подходе
@export var chaos_pause_min_base: float       = 0.05   # минимальная длительность паузы (сек)
@export var chaos_pause_max_base: float       = 0.30   # максимальная длительность паузы (сек)

@export var chaos_backstep_chance_base: float = 0.10   # шанс сделать шаг назад (обманка)
@export var chaos_backstep_dist_base: float   = 0.10   # длина шага назад по X
@export var chaos_backstep_steps_base: int    = 1      # количество шагов подряд (обычно 1–2)
@export var chaos_backstep_step_time_base: float = 0.18 # длительность одного шага назад (сек)
@export var chaos_decision_interval_base: float = 0.35  # как часто можно принимать новое хаотичное решение
@export var chaos_idle_grace_base: float = 0.35         # минимальная «передышка» после паузы/бэкстепа

# --- Боевые дистанции (точные допуски по X и Z) ---
@export_category("Combat / Distances")
@export_range(0.0, 5.0, 0.01)
var attack_x_window: float = 0.18      # горизонтальный допуск для начала атаки
@export_range(0.0, 5.0, 0.01)
var attack_z_window: float = 0.30      # допуск по глубине (ось Z) для атаки
@export_range(0.0, 5.0, 0.01)
var approach_stop_x: float = 0.35      # целевая дистанция по X, на которой враг останавливается
@export_range(0.0, 5.0, 0.01)
var approach_x_window: float = 0.10    # «мертвая зона» вокруг stop_x (гистерезис)
