#!/usr/bin/env ruby
# fish.rb - a boids
#
# Copyright (c) 2013 Takeshi Tomaru
#
# See COPYING for license

require 'matrix'
require 'tk'
require 'tkextlib/tile'

class World
  X, Y = 300, 300
  MAX_FISHES = 30

  attr_reader :x, :y
  attr_reader :canvas
  attr_reader :fishes, :rocks

  def initialize(canvas)
    @mutex = Mutex.new
    @x, @y = X, Y
    @canvas = canvas
    @canvas['width'] = @x
    @canvas['height'] = @y
    @fishes = []
    (rand(3..MAX_FISHES)).times do
      @fishes << Fish.new(self)
      @fishes.last.draw()
    end
    @rocks = []
  end

  def tick
    begin
      return unless @mutex.try_lock

      make_rock() if rand(80) == 0
      @fishes.each do |fish|
        fish.do_actions()
      end
      @fishes.each do |fish|
        fish.move()
        wrap_world(fish)
        fish.redraw()
      end
    rescue => e
      # catch and show exceptions in a tk thread
      Tk::messageBox(message: "#{e.to_s}\n#{$@}")
      raise e
    ensure
      @mutex.unlock
   end
  end

  def wrap_world(fish)
    # fish cannot get out from the world
    if fish.position[0] < 0
      fish.position = fish.position + Vector[@x, 0]
    elsif fish.position[0] >= @x
      fish.position = fish.position - Vector[@x, 0]
    end
    if fish.position[1] < 0
      fish.position = fish.position + Vector[0, @y]
    elsif fish.position[1] >= @y
      fish.position = fish.position - Vector[0, @y]
    end
  end

  def make_rock
    @rocks << Rock.new(self)
    @rocks.last.draw()
  end
end

class Rock
  MAX_RADIUS =  15

  attr_reader :position, :radius

  def initialize(world)
    @world = world
    @position = Vector[rand(@world.x), rand(@world.y)]
    @radius = rand(MAX_RADIUS) + 1
  end

  def draw
    @rock = TkcOval.new(@world.canvas,
                        @position[0] - @radius,
                        @position[1] - @radius,
                        @position[0] + @radius,
                        @position[1] + @radius) { outline 'gray' }
  end
end

class Fish
  PI2 = Math::PI * 2
  BODY_R = 5
  EYESIGHT = 50
  AOV = Math::PI * 3 / 4  # angle of view
  MAX_VELOCITY = 20
  RAD_TO_DEG = 180 / Math::PI
  AOV_IN_DEG = AOV * RAD_TO_DEG

  attr_accessor :position, :velocity

  def initialize(world)
    @world = world
    @position = Vector[rand(@world.x), rand(@world.y)]
    velocity = rand(MAX_VELOCITY) + 1
    angle = rand(0...PI2)
    @velocity = Vector[Integer(velocity * Math.cos(angle)),
                       Integer(velocity * Math.sin(angle))]
  end

  def move
    @velocity += @adjustment
    # fish cannot swim at MAX_VELOCITY or faster speed
    if @velocity.r > MAX_VELOCITY
      @velocity = @velocity / (@velocity.r / MAX_VELOCITY)
    end

    @velocity = @velocity.map(&:to_i)
    @old_position = @position
    @position += @velocity
  end

  def do_actions
    @adjustment = dodge_rocks()
    @adjustment = boids() unless @adjustment.r > 0
  end

  def dodge_rocks
    adjustment = Vector[0, 0]
    rocks = get_objects_in_fov(@world.rocks)
    if rocks.size > 0
      rocks.each do |rock|
        distance = @position - rock.position
        adjustment += distance * rock.radius * 2 / distance.r
      end
    end
    adjustment
  end

  def boids
    fishes = get_objects_in_fov(@world.fishes)
    return Vector[0, 0] unless fishes.size > 0

    adjustment = Vector[0, 0]
    sep_velocity = Vector[0, 0]
    group_velocity = Vector[0, 0]
    center = Vector[0, 0]

    fishes.first(4).each do |fish|
      distance = @position - fish.position
      if distance.r <= BODY_R * 4 && distance.r > 0
        sep_velocity += distance * 8 / distance.r
      end
      group_velocity += fish.velocity
      center += fish.position
    end
    # Separation
    adjustment += sep_velocity
    # Alignment
    adjustment += group_velocity / fishes.size
    # Cohesion
    adjustment += (center / fishes.size) - @position
  end

  # objects in my field of vision
  def get_objects_in_fov(objects)
    in_fov = []
    objects.each do |object|
      next if object == self
      next if (object.position - @position).r > EYESIGHT
      angle_of_velocity = Math.atan2(-@velocity[1], @velocity[0])
      angle_to_other = Math.atan2(-(object.position[1] - @position[1]),
                                  object.position[0] - @position[0])
      next if (angle_to_other - angle_of_velocity).abs > AOV
      in_fov << object
    end
    in_fov
  end

  def draw
    @body = TkcOval.new(@world.canvas,
                        @position[0] - BODY_R,
                        @position[1] - BODY_R,
                        @position[0] + BODY_R,
                        @position[1] + BODY_R) { outline 'blue' }
    @tail = TkcLine.new(@world.canvas,
                        @position[0],
                        @position[1],
                        @position[0] - @velocity[0],
                        @position[1] - @velocity[1]) { fill 'blue' }
#    angle_of_velocity = Math.atan2(-@velocity[1], @velocity[0])
#     @eyesight = TkcArc.new(@world.canvas,
#                            @position[0] - EYESIGHT,
#                            @position[1] - EYESIGHT,
#                            @position[0] + EYESIGHT,
#                            @position[1] + EYESIGHT) do
#                              start angle_of_velocity * RAD_TO_DEG - AOV_IN_DEG
#                              extent AOV_IN_DEG * 2
#                              dash '.   '
#                              outline '#bebe90'
#                            end

  end

  def redraw
    delta = @position - @old_position
    @body.move(delta[0], delta[1])
    @tail.coords(@position[0],
                 @position[1],
                 @position[0] - @velocity[0],
                 @position[1] - @velocity[1])
#    @eyesight.move(delta[0], delta[1])
#    angle_of_velocity = Math.atan2(-@velocity[1], @velocity[0])
#    @eyesight['start'] = angle_of_velocity * RAD_TO_DEG - AOV_IN_DEG
  end
end

root = TkRoot.new { title 'Fish' }
canvas = TkCanvas.new(root).grid
world = World.new(canvas)
TkAfter.new(50, 1000, proc { world.tick() }).start()
Tk.mainloop()
