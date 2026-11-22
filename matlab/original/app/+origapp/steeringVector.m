function sv = steeringVector(ula, fc, ang)
%STEERINGVECTOR Same as phased.SteeringVector('SensorArray',ula) called with (fc,ang),
% with the System object kept between frames: constructing it on every frame cost
% about 6 ms. One object per element-position set and angle-input size (a locked
% System object keeps its input size); at most 8 are kept.
persistent cache
pos = getElementPosition(ula);
key = [size(ang) pos(:).'];
if isempty(cache), cache = struct('key', {}, 'obj', {}); end
k = 0;
for j = 1:numel(cache)
    if isequal(cache(j).key, key), k = j; break, end
end
if k == 0
    cache(end+1) = struct('key', key, 'obj', phased.SteeringVector('SensorArray', clone(ula)));
    if numel(cache) > 8, cache(1) = []; end
    k = numel(cache);
end
sv = cache(k).obj(fc, ang);
end
