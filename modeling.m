
modelName = bdroot(gcs);           % Получаем имя текущей модели
blks = find_system(modelName, 'BlockType', 'SubSystem');  % Ищем все подсистемы
names = get_param(blks, 'Name');   % Функция get_param корректно принимает cell array
disp(names);                       % Выводим список в консоль

sim('plant')


