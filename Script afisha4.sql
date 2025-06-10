--
--Исследовательский анализ данных сервиса бронирования билетов Яндекс.Афиша.
--
--Выполнила: Ложникова Елена
--Дата: 30.05.2025
--
--Часть 1: Анализ данных с помощью SQL и создание дашборда в DataLens. Знакомство с данными
--
--1.1. Взаимосвязь таблиц
--Какие поля являются первичными ключами в таблицах, а какие — внешними. 
--
SELECT table_name, 
    column_name, 
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'afisha'
    AND table_name IN ('purchases', 'events', 'city_id', 'regions')
ORDER BY  table_name, ordinal_position;


--table_name|column_name           |data_type                  |is_nullable|column_default|
------------+----------------------+---------------------------+-----------+--------------+
--events    |event_id              |integer                    |NO         |              |
--events    |event_name_code       |character varying          |YES        |              |
--events    |event_type_description|character varying          |YES        |              |
--events    |event_type_main       |character varying          |YES        |              |
--events    |organizers            |character varying          |YES        |              |
--events    |city_id               |integer                    |YES        |              |
--events    |venue_id              |integer                    |YES        |              |
--purchases |order_id              |integer                    |NO         |              |
--purchases |user_id               |character varying          |YES        |              |
--purchases |created_dt_msk        |timestamp without time zone|YES        |              |
--purchases |created_ts_msk        |timestamp without time zone|YES        |              |
--purchases |event_id              |integer                    |YES        |              |
--purchases |cinema_circuit        |character varying          |YES        |              |
--purchases |age_limit             |integer                    |YES        |              |
--purchases |currency_code         |character varying          |YES        |              |
--purchases |device_type_canonical |character varying          |YES        |              |
--purchases |revenue               |real                       |YES        |              |
--purchases |service_name          |character varying          |YES        |              |
--purchases |tickets_count         |integer                    |YES        |              |
--purchases |total                 |real                       |YES        |              |
--regions   |region_id             |integer                    |NO         |              |
--regions   |region_name           |character varying          |YES        |              |
 
--Первичные ключи (Primary Keys):
--events: event_id (integer) - основной идентификатор события
--purchases: order_id (integer) - уникальный идентификатор заказа
--regions: region_id (integer) - уникальный идентификатор региона

--Внешние ключи (Foreign Keys)
-- в таблице events: city_id → вероятно ссылается на region_id в таблице regions
--в таблице purchases: event_id → ссылается на event_id в таблице events



--Оцените типы связей: встречаются ли между таблицами отношения «один к одному», «один ко многим» или «многие ко многим».
--   
SELECT conrelid::regclass AS source_table,
    a.attname AS source_column,
    confrelid::regclass AS target_table,
    af.attname AS target_column,
    CASE 
        WHEN con.contype = 'f' THEN 'one-to-many (1:N)'
    END AS relationship_type
FROM
    pg_constraint con
    JOIN pg_attribute a ON a.attnum = con.conkey[1] AND a.attrelid = con.conrelid
    JOIN pg_attribute af ON af.attnum = con.confkey[1] AND af.attrelid = con.confrelid
WHERE
    con.contype = 'f'
    AND con.connamespace = 'afisha'::regnamespace;
   
   
--source_table    |source_column|target_table  |target_column|relationship_type|
------------------+-------------+--------------+-------------+-----------------+
--afisha.city     |region_id    |afisha.regions|region_id    |one-to-many (1:N)|
--afisha.events   |city_id      |afisha.city   |city_id      |one-to-many (1:N)|
--afisha.events   |venue_id     |afisha.venues |venue_id     |one-to-many (1:N)|
--afisha.purchases|event_id     |afisha.events |event_id     |one-to-many (1:N)|
--afisha.purchases|event_id     |afisha.events |event_id     |one-to-many (1:N)|   
   

 
----Отношения «один ко многим» (1:N) - основной тип связей в схеме afisha:
----events ← purchases. Одно событие (events) может иметь много покупок (purchases).Внешний ключ: purchases.event_id → events.event_id
----city_id ← events. Один город может иметь много событий. Внешний ключ: events.city_id → city_id.city_id
----regions ← city_id. Один регион может содержать много городов. Внешний ключ: city_id.region_id → regions.region_id.
   
   

--1.2. 
  --Содержимое таблиц. Проверим соответствуют ли данные описанию и в каком объёме они представлены.
--
-- Для таблицы purchases
--   
SELECT COUNT(*) AS total_orders,
    COUNT(DISTINCT user_id) AS unique_users,
    pg_size_pretty(pg_total_relation_size('afisha.purchases')) AS table_size
from afisha.purchases;  


--total_orders|unique_users|table_size|
--------------+------------+----------+
--      292034|       22000|45 MB     |
   


-- Для таблицы events
--   
SELECT 'events' AS table_name,
    COUNT(*) AS row_count,
    pg_size_pretty(pg_total_relation_size('afisha.events')) AS table_size
FROM afisha.events;


--table_name|row_count|table_size|
------------+---------+----------+
--events    |    22484|3184 kB   |
    


-- Для таблицы city
--   
SELECT 'city_id' AS table_name,
    COUNT(*) AS row_count,
    pg_size_pretty(pg_total_relation_size('afisha.city')) AS table_size
from afisha.city;


--table_name|row_count|table_size
------------+---------+----------
--city_id   |      353|64 kB     
 

-- Для таблицы regions
--   
SELECT 'regions' AS table_name,
    COUNT(*) AS row_count,
    pg_size_pretty(pg_total_relation_size('afisha.regions')) AS table_size
from afisha.regions; 

--table_name|row_count|table_size|
------------+---------+----------+
--regions   |       81|24 kB     |
 
   
----Данные хорошо сбалансированы: нет перекоса в размерах таблицс, оотношения записей соответствуют ожидаемой бизнес-логике, 
----размеры позволяют работать без сложной оптимизации.  

   
--1.3. 
  --Корректность данных. 
  --Проверьте уникальность идентификаторов, наличие пропусков, корректность написания категориальных данных, 
  --например типов устройств, названий городов и регионов, кодов валюты.
--
--1.3.1. Проверка уникальности purchases.order_id
--
SELECT 
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS unique_orders,
    CASE 
        WHEN COUNT(*) = COUNT(DISTINCT order_id) THEN 'OK: Все order_id уникальны'
        ELSE 'Ошибка: Есть дубликаты order_id'
    END AS check_result
FROM afisha.purchases;

--total_rows|unique_orders|check_result              |
------------+-------------+--------------------------+
--    292034|       292034|OK: Все order_id уникальны|



-- Проверка уникальности events.event_id
--
SELECT 
    COUNT(*) AS total_events,
    COUNT(DISTINCT event_id) AS unique_events,
    CASE 
        WHEN COUNT(*) = COUNT(DISTINCT event_id) THEN 'OK: Все event_id уникальны'
        ELSE 'Ошибка: Есть дубликаты event_id'
    END AS check_result
FROM afisha.events;

--total_events|unique_events|check_result              |
--------------+-------------+--------------------------+
--       22484|        22484|OK: Все event_id уникальны|


----Идентификаторы order_id, event_id уникальны.



SELECT
    COUNT(DISTINCT event_id) AS unique_event_ids,
    COUNT(DISTINCT event_name_code) AS unique_event_codes,
    COUNT(DISTINCT CASE WHEN event_name_code IS NOT NULL THEN event_id END) AS events_with_code,
    COUNT(DISTINCT CASE WHEN event_name_code IS NULL THEN event_id END) AS events_without_code
from afisha.events;

--unique_event_ids|unique_event_codes|events_with_code|events_without_code|
------------------+------------------+----------------+-------------------+
--           22484|             15287|           22484|                  0|
   
   
----Количество уникальных событий по event_id больше, чем по идентификатору названия события event_name_code. 
----Одно и то же событие могло проводиться в разных городах на разных площадках.   



--1.3.2. Проверка пропусков в критических полях.
--
-- Проверка таблицы purchases
--
SELECT
    'purchases' AS table_name,
    COUNT(*) FILTER (WHERE order_id IS NULL) AS null_order_id,
    COUNT(*) FILTER (WHERE user_id IS NULL) AS null_user_id,
    COUNT(*) FILTER (WHERE event_id IS NULL) AS null_event_id,
    COUNT(*) FILTER (WHERE revenue IS NULL) AS null_revenue,
    COUNT(*) FILTER (WHERE tickets_count IS NULL) AS null_tickets,
    COUNT(*) FILTER (WHERE created_dt_msk IS NULL) AS null_date,
    ROUND(COUNT(*) FILTER (WHERE device_type_canonical IS NULL) * 100.0 / COUNT(*), 2) AS percent_null_device
FROM afisha.purchases;

--table_name|null_order_id|null_user_id|null_event_id|null_revenue|null_tickets|null_date|percent_null_device|
------------+-------------+------------+-------------+------------+------------+---------+-------------------+
--purchases |            0|           0|            0|           0|           0|        0|               0.00|



-- Проверка таблицы events
--
SELECT
    'events' AS table_name,
    COUNT(*) FILTER (WHERE event_id IS NULL) AS null_event_id,
    COUNT(*) FILTER (WHERE event_type_main IS NULL) AS null_type,
    COUNT(*) FILTER (WHERE city_id IS NULL) AS null_city_id,
    ROUND(COUNT(*) FILTER (WHERE organizers IS NULL) * 100.0 / COUNT(*), 2) AS percent_null_organizers
FROM afisha.events;

--table_name|null_event_id|null_type|null_city_id|percent_null_organizers|
------------+-------------+---------+------------+-----------------------+
--events    |            0|        0|           0|                   0.00|



--Проверка таблицы regions
--
SELECT
    'regions' AS table_name,
    COUNT(*) FILTER (WHERE region_id IS NULL) AS null_region_id,
    COUNT(*) FILTER (WHERE region_name IS NULL) AS null_region_name
FROM afisha.regions;

--table_name|null_region_id|null_region_name|
------------+--------------+----------------+
--regions   |             0|               0|



--Проверка таблицы city
--
SELECT
    'city' AS table_name,
    COUNT(*) FILTER (WHERE city_id IS NULL) AS null_city_id,
    COUNT(*) FILTER (WHERE city_name IS NULL) AS null_city_name,
    COUNT(*) FILTER (WHERE region_id IS NULL) AS null_region_id
FROM afisha.city;

--table_name|null_city_id|null_city_name|null_region_id|
------------+------------+--------------+--------------+
--city      |           0|             0|             0|


----Пропуски отсутствуют во всех таблицах.



--1.3.3. Проверка корректности написания категориальных данных, например типов устройств, названий городов и регионов, кодов валюты.
--
--Типы устройств
--
SELECT 
    device_type_canonical,
    COUNT(*) AS device_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM afisha.purchases), 2) AS percent
FROM afisha.purchases
GROUP BY device_type_canonical
ORDER BY device_count DESC;

--device_type_canonical|device_count|percent|
-----------------------+------------+-------+
--mobile               |      232679|  79.68|
--desktop              |       58170|  19.92|
--tablet               |        1180|   0.40|
--tv                   |           3|   0.00|
--other                |           2|   0.00|

----Мобильные устройства доминируют - 79.68% покупок.
----Десктопы на втором месте: 19.92% транзакций.
----Редкие устройства: планшеты (0.4%) и 5 записей TV и other— возможно, ошибочные записи или тестовые данные.



--Коды валют
--
SELECT 
    currency_code,
    COUNT(*) AS transaction_count
FROM afisha.purchases
GROUP BY currency_code
ORDER BY transaction_count DESC;

--currency_code|transaction_count|
---------------+-----------------+
--rub          |           286961|
--kzt          |             5073|


----Подавляющее большинство в RUB: 286,961 операций.
----KZT (казахстанские тенге): 5,073 операций.



--Названия городов и регионов
--
-- Проверка регионов
--
SELECT 
    region_name,
    COUNT(*) AS city_count
FROM afisha.regions r
JOIN afisha.city c ON r.region_id = c.region_id
GROUP BY region_name
ORDER BY region_name;

--region_name              |city_count|
---------------------------+----------+
--Белоярская область       |         2|
--Берестовский округ       |         1|
--Берёзовская область      |         3|
--Боровлянский край        |         4|
--Верховинская область     |         1|
--Верхозёрский край        |         1|
--Верхоречная область      |         1|
--Ветренский регион        |         2|
--Вишнёвский край          |         2|
--Глиногорская область     |         4|
--Голубевский округ        |         3|
--Горицветская область     |        14|
--Горноземский регион      |         2|
--Горностепной регион      |         8|
--Дальнеземская область    |         4|
--Дальнезорский край       |         3|
--Дубравная область        |         1|
--Залесский край           |         3|
--Заречная область         |        14|
--Зеленоградский округ     |         4|
--Златопольский округ      |         1|
--Золотоключевской край    |        10|
--Зоринский регион         |         1|
--Каменевский регион       |        32|
--Каменичская область      |         3|
--Каменноозёрный край      |         3|
--Каменноярский край       |         9|
--Каменополянский округ    |         3|
--Ключеводский округ       |         4|
--Кристаловская область    |         3|
--Кристальная область      |         4|
--Крутоводская область     |         1|
--Крутоводский регион      |         2|
--Лесноярский край         |         1|
--Лесодальний край         |         3|
--Лесополянская область    |         1|
--Лесостепной край         |         3|
--Лесоярская область       |         1|
--Луговая область          |         5|
--Лугоградская область     |         2|
--Малиновая область        |         3|
--Малиновоярский округ     |         4|
--Медовская область        |         6|
--Миропольская область     |         4|
--Нежинская область        |         2|
--Озернинский край         |         3|
--Озернопольская область   |         1|
--Островная область        |         1|
--Островогорский округ     |         1|
--Поленовский край         |         4|
--Радужногорская область   |         1|
--Радужнопольский край     |         1|
--Речиновская область      |         1|
--Речицкая область         |         1|
--Речицкий регион          |         1|
--Ручейковский край        |         6|
--Светолесский край        |         1|
--Светополянский округ     |        19|
--Североключевской округ   |         4|
--Североозёрский округ     |         6|
--Североярская область     |         6|
--Серебринская область     |         9|
--Серебряноярский округ    |         2|
--Синегорский регион       |         2|
--Солнечноземская область  |        10|
--Солнечнореченская область|        21|
--Сосноводолинская область |         1|
--Сосновская область       |         1|
--Теплоозёрский округ      |         1|
--Тепляковская область     |         8|
--Тихогорская область      |         2|
--Тихолесский край         |         1|
--Тихореченская область    |         2|
--Травиницкий округ        |         5|
--Травяная область         |         7|
--Чистогорская область     |         3|
--Шанырский регион         |         2|
--Широковская область      |        15|
--Яблоневская область      |         7|
--Ягодиновская область     |         5|
--Яснопольский округ       |         4|

----Распределение городов: Каменевский регион (32 города) — явный выброс


-- Поиск возможных опечаток в городах
--
SELECT 
    city_name,
    COUNT(*) AS dup_count
FROM afisha.city
GROUP BY city_name
HAVING COUNT(*) > 1
ORDER BY dup_count DESC;

--city_name |dup_count|
------------+---------+
--Глинополье|        2|

----Дубликат города: "Глинополье" встречается 2 раза.



SELECT c.*, r.region_name 
FROM afisha.city c
JOIN afisha.regions r ON c.region_id = r.region_id
WHERE c.city_name = 'Глинополье';

--city_id|city_name |region_id|region_name            |
---------+----------+---------+-----------------------+
--  11101|Глинополье|      911|Голубевский округ      |
--     56|Глинополье|      917|Солнечноземская область|



--1.4. Распределение заказов по основным категориям. 
     --Например, по типам мероприятий, устройствам, кодам валюты и другим категориям.
--
-- Распределение заказов по категориям
--
---- По типам устройств
--
SELECT 'device_type' AS category,
        device_type_canonical AS value,
        COUNT(*) AS order_count,
        ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM afisha.purchases), 2) AS percentage_value
    FROM afisha.purchases
    GROUP BY device_type_canonical
    order by order_count DESC;
   
--category   |value  |order_count|percentage_value|
-------------+-------+-----------+----------------+
--device_type|mobile |     232679|           79.68|
--device_type|desktop|      58170|           19.92|
--device_type|tablet |       1180|            0.40|
--device_type|tv     |          3|            0.00|
--device_type|other  |          2|            0.00|   
   
--Доминирование мобильных устройств - 79.68% всех заказов.
--Это указывает на критическую важность мобильной оптимизации платформы.
--Десктопная версия генерирует 19.92% заказов, почти каждый 5-й заказ делается с компьютера.
--Планшеты (tablet) - всего 0.4% (незначительная доля)
--TV и другие устройства - статистически незначимы (<0.01%)   
   

   
---- По кодам валют
--
    SELECT 'currency' AS category,
           currency_code AS value,
           COUNT(*) AS order_count,
           ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM afisha.purchases), 2) AS percentage_value
    FROM afisha.purchases
    GROUP BY currency_code
    order by order_count DESC;
   
--category|value|order_count|percentage_value|
----------+-----+-----------+----------------+
--currency|rub  |     286961|           98.26|
--currency|kzt  |       5073|            1.74|

--Основной рынок - Россия (Основной рынок - Россия (RUB) - 98.26%.
--Казахстан (KZT) представлен минимально).

     
   
-- По сервисам
--   
    SELECT 'service' AS category,
           service_name AS value,
           COUNT(*) AS order_count,
           ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM afisha.purchases), 2) AS percentage_value
    FROM afisha.purchases
    GROUP BY service_name
    order by order_count DESC;
   
--category|value                 |order_count|percentage_value|
----------+----------------------+-----------+----------------+
--service |Билеты без проблем    |      63932|           21.89|
--service |Лови билет!           |      41338|           14.16|
--service |Билеты в руки         |      40500|           13.87|
--service |Мой билет             |      34965|           11.97|
--service |Облачко               |      26730|            9.15|
--service |Лучшие билеты         |      17872|            6.12|
--service |Весь в билетах        |      16910|            5.79|
--service |Прачечная             |      10385|            3.56|
--service |Край билетов          |       6238|            2.14|
--service |Тебе билет!           |       5242|            1.79|
--service |Яблоко                |       5057|            1.73|
--service |Дом культуры          |       4514|            1.55|
--service |За билетом!           |       2877|            0.99|
--service |Городской дом культуры|       2747|            0.94|
--service |Show_ticket           |       2208|            0.76|
--service |Мир касс              |       2171|            0.74|
--service |Быстробилет           |       2010|            0.69|
--service |Выступления.ру        |       1621|            0.56|
--service |Восьмёрка             |       1126|            0.39|
--service |Crazy ticket!         |        796|            0.27|
--service |Росбилет              |        544|            0.19|
--service |Шоу начинается!       |        499|            0.17|
--service |Быстрый кассир        |        381|            0.13|
--service |Радио ticket          |        380|            0.13|
--service |Телебилет             |        321|            0.11|
--service |КарандашРУ            |        133|            0.05|
--service |Реестр                |        130|            0.04|
--service |Билет по телефону     |         85|            0.03|
--service |Вперёд!               |         81|            0.03|
--service |Дырокол               |         74|            0.03|
--service |Кино билет            |         67|            0.02|
--service |Цвет и билет          |         61|            0.02|
--service |Тех билет             |         22|            0.01|
--service |Лимоны                |          8|            0.00|
--service |Зе Бест!              |          5|            0.00|
--service |Билеты в интернете    |          4|            0.00|   
   

--ТОП-4 сервиса формируют ~62% всех заказов: "Билеты без проблем" (21.89%),"Лови билет!" (14.16%), "Билеты в руки" (13.87%), "Мой билет" (11.97%).
--Средние сервисы (5–10% доля): "Облачко" (9.15%), "Лучшие билеты" (6.12%), "Весь в билетах" (5.79%).
--Длинный хвост малозначимых сервисов (менее 5%): 25+ сервисов с долей <5%, многие — менее 1%.

   
   
-- По возрастным ограничениям
--   
    SELECT 'age_limit' AS category,
           age_limit::text AS value,
           COUNT(*) AS order_count,
           ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM afisha.purchases), 2) AS percentage_value
    FROM afisha.purchases
    GROUP BY age_limit 
    order by order_count DESC;
   
--category |value|order_count|percentage_value|
-----------+-----+-----------+----------------+
--age_limit|16   |      78864|           27.01|
--age_limit|12   |      62861|           21.53|
--age_limit|0    |      61731|           21.14|
--age_limit|6    |      52403|           17.94|
--age_limit|18   |      36175|           12.39| 

--Большинство мероприятий ориентированы на подростков и семейную аудиторию (12+, 16+, 6+).
--18+ (концерты, вечеринки?) менее востребованы, но есть стабильный спрос.
--0+ (детские спектакли, мультфильмы) — пятая часть заказов.   
   
   
   
-- По количеству билетов
--   
    SELECT 'tickets_count' AS category,
        CASE 
            WHEN tickets_count = 1 THEN '1 билет'
            WHEN tickets_count = 2 THEN '2 билета'
            WHEN tickets_count BETWEEN 3 AND 5 THEN '3-5 билетов'
            ELSE '6+ билетов'
        END AS value,
        COUNT(*) AS order_count,
        ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM afisha.purchases), 2) AS percentage_value
    FROM afisha.purchases
    GROUP BY 
        CASE 
            WHEN tickets_count = 1 THEN '1 билет'
            WHEN tickets_count = 2 THEN '2 билета'
            WHEN tickets_count BETWEEN 3 AND 5 THEN '3-5 билетов'
            ELSE '6+ билетов'
        end
    order by order_count DESC;
   
 --category     |value      |order_count|percentage_value|
---------------+-----------+-----------+----------------+
--tickets_count|3-5 билетов|     161345|           55.25|
--tickets_count|2 билета   |      84240|           28.85|
--tickets_count|1 билет    |      41963|           14.37|
--tickets_count|6+ билетов |       4486|            1.54|  

--Пользователи чаще покупают на компанию/семью (3–5 билетов).
--Парные покупки (2 билета) — вероятно, пары или друзья.
--Одиночные заказы (1 билет) — менее популярны, но есть стабильный спрос.
--Крупные заказы (6+) — очень редки (возможно, корпоративные или группы).   
   
   
   
--По типу мероприятия 
--   
SELECT 'event_type' AS type,
        event_type_main AS valuee,
        COUNT(*) AS order_count,
        ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM afisha.purchases), 2) AS percentage_value
FROM afisha.events
GROUP BY event_type_main
order by order_count DESC;

--type      |valuee  |order_count|percentage_value|
------------+--------+-----------+----------------+
--event_type|концерты|       8699|            2.98|
--event_type|театр   |       7090|            2.43|
--event_type|другое  |       4662|            1.60|
--event_type|спорт   |        872|            0.30|
--event_type|стендап |        636|            0.22|
--event_type|выставки|        291|            0.10|
--event_type|ёлки    |        215|            0.07|
--event_type|фильм   |         19|            0.01|

--Концерты - самые популярные с наибольшим количеством заказов и самой высокой долей в выручке.
--На втором месте - театральные мероприятия.
--Самые низкие показатели у фильмов и ёлок.




--1.5.
--Проверка возможных анамалий или некорректных значений в данных. 
--Например, изучите статистические данные по полю выручки: встречаются ли выбросы или другие особенности.
--
-- Базовая статистика по выручке
--
SELECT COUNT(*) AS total_orders,
    ROUND(AVG(revenue)::numeric, 2) AS avg_revenue,
    MIN(revenue) AS min_revenue,
    MAX(revenue) AS max_revenue,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY revenue) AS median_revenue,
    STDDEV(revenue) AS revenue_stddev,
    COUNT(*) FILTER (WHERE revenue < 0) AS negative_revenue_count,
    COUNT(*) FILTER (WHERE revenue = 0) AS zero_revenue_count,
    COUNT(*) FILTER (WHERE revenue > 100000) AS high_revenue_count
FROM afisha.purchases;

--total_orders|avg_revenue|min_revenue|max_revenue|median_revenue   |revenue_stddev    |negative_revenue_count|zero_revenue_count|high_revenue_count|
--------------+-----------+-----------+-----------+-----------------+------------------+----------------------+------------------+------------------+
--      292034|     624.83|     -90.76|   81174.54|355.3399963378906|1225.6956939277632|                   381|              5772|                 0|


----Сильный разброс значений: средняя выручка заказа: 624.83, медианная выручка: 355.34 (значительно ниже среднего, что указывает на правостороннюю асимметрию — много дешевых заказов и немного очень дорогих)
----Максимальная выручка: 81,174.54 (аномально высокое значение). Стандартное отклонение: 1,225.70 (высокая волатильность)
----381 заказ с отрицательной выручкой (возвраты или ошибки)
----5,772 заказов с нулевой выручкой (бесплатные билеты или ошибки)


-- Топ-10 самых дорогих заказов
--
SELECT order_id,
       user_id,
       event_id,
       revenue,
       tickets_count,
       ROUND(((revenue/tickets_count)::numeric), 2) AS price_per_ticket
FROM afisha.purchases
ORDER BY revenue DESC
LIMIT 10;

--order_id|user_id        |event_id|revenue |tickets_count|price_per_ticket|
----------+---------------+--------+--------+-------------+----------------+
-- 8067453|96368e5714d1673|  552398|81174.54|            5|        16234.91|
-- 4113477|5b5714894bd0517|  552398|81174.54|            5|        16234.91|
-- 4113535|5b5714894bd0517|  552398|81174.54|            5|        16234.91|
-- 4299860|c9d333921d46129|  552398|64939.63|            4|        16234.91|
-- 6492608|52d3acc2caf432d|  552398|64939.63|            4|        16234.91|
-- 8330309|5245e419c5ac876|  552398|64939.63|            4|        16234.91|
-- 4113506|5b5714894bd0517|  552398|64939.63|            4|        16234.91|
-- 7150734|a6021dd115eba1e|  552398|64939.63|            4|        16234.91|
-- 3246754|1f49b8de206b285|  552398|48704.72|            3|        16234.91|
-- 2147799|aa3947877dd78f9|  552398|48704.72|            3|        16234.91|


----Несколько дорогих заказов с выручкой > 48,000 (например, 81,174.54 за 5 билетов, 16,234.91 за билет).
----Все они относятся к одному мероприятию (event_id = 552398) — возможно, VIP-билеты или ошибка в данных.



-- Топ-10 подозрительно дешевых заказов
--
SELECT order_id,
       user_id,
       event_id,
       revenue,
       tickets_count
FROM afisha.purchases
WHERE revenue > 0
ORDER BY revenue ASC
LIMIT 10;

--order_id|user_id        |event_id|revenue|tickets_count|
---------+---------------+--------+-------+-------------+
-- 1901125|44d32ef1ecfd4fa|  387935|   0.02|            1|
-- 7273607|a129c1c38d5092f|  387935|   0.02|            1|
--  983275|f3011061eb55e24|  387935|   0.02|            1|
-- 7658408|2d40f3cf88ee120|  387935|   0.02|            1|
-- 5663063|0eed023b8630964|  387935|   0.04|            2|
-- 7273578|a129c1c38d5092f|  387935|   0.04|            2|
-- 6343084|4c96e2a46134b1c|  567579|   0.05|            1|
-- 6343113|4c96e2a46134b1c|  567579|   0.05|            1|
-- 1968463|8187dac4be757a0|  567579|   0.05|            1|
-- 4414323|18e9aead0a393e7|  578647|   0.05|            1|


----Подозрительно дешевые заказы: билеты по 0.02–0.05, сконцентрированы на мероприятиях 387935, 567579, 578647 — возможно, тестовые данные или акции.



-- Статистика по цене билета (выручка/количество билетов)
--
WITH ticket_prices AS (
    SELECT
        revenue/tickets_count AS price_per_ticket
    FROM afisha.purchases
    WHERE tickets_count > 0 AND revenue > 0
)
SELECT
    COUNT(*) AS orders_with_valid_price,
    ROUND(AVG(price_per_ticket::numeric), 2) AS avg_price,
    MIN(price_per_ticket) AS min_price,
    MAX(price_per_ticket) AS max_price,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_per_ticket) AS median_price,
    STDDEV(price_per_ticket) AS price_stddev
FROM ticket_prices;

--orders_with_valid_price|avg_price|min_price           |max_price    |median_price      |price_stddev      |
-------------------------+---------+--------------------+-------------+------------------+------------------+
--                 285881|   231.75|0.019999999552965164|21757.5390625|157.18000284830728|422.39318796308186|

----Средняя цена билета: 231.75
----Медианная цена: 157.18 (разница с средним подтверждает наличие выбросов)
----Разброс цен: Минимум: 0.02 (ошибка или акция), Максимум: 21,757.54 (аномалия)


-- Средняя выручка по типам мероприятий
--
SELECT e.event_type_main,
    COUNT(*) AS order_count,
    ROUND(AVG(p.revenue::numeric), 2) AS avg_revenue,
    ROUND(MIN(p.revenue::numeric), 2) AS min_revenue,
    ROUND(MAX(p.revenue::numeric), 2) AS max_revenue
FROM afisha.purchases p
JOIN afisha.events e ON p.event_id = e.event_id
GROUP BY e.event_type_main
ORDER BY avg_revenue DESC;

--event_type_main|order_count|avg_revenue|min_revenue|max_revenue|
-----------------+-----------+-----------+-----------+-----------+
--концерты       |     115634|     974.91|      -5.70|   81174.50|
--ёлки           |       2006|     772.36|      26.02|    4362.15|
--стендап        |      13424|     712.51|       3.97|   24680.90|
--театр          |      67744|     548.36|       0.00|    8161.31|
--другое         |      66109|     250.27|     -17.94|    9543.40|
--выставки       |       4873|     233.10|      -6.33|    3656.87|
--спорт          |      22006|     172.38|     -90.76|   18641.90|
--фильм          |        238|      12.96|       0.00|     236.24|

----Концерты — самые доходные (средний чек в 2 раза выше медианного по всем заказам).
----Кино — незначительная доля в выручке (всего 238 заказов).



-- Средняя выручка по коду валюты
--
SELECT currency_code,
    COUNT(DISTINCT user_id) AS total_users,
    COUNT(*) AS orders_count,
    ROUND(SUM(revenue::numeric), 2) AS total_revenue,
    ROUND(AVG(revenue::numeric), 2) AS avg_revenue,
    MIN(revenue) AS min_revenue,
    MAX(revenue) AS max_revenue,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY revenue) AS median_revenue,
    COUNT(*) FILTER (WHERE revenue < 0) AS negative_orders,
    COUNT(*) FILTER (WHERE revenue = 0) AS zero_orders,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM afisha.purchases), 2) AS percentage_of_total
FROM
    afisha.purchases
GROUP by currency_code
ORDER by total_revenue DESC;

--currency_code|total_users|orders_count|total_revenue|avg_revenue|min_revenue|max_revenue|median_revenue    |negative_orders|zero_orders|percentage_of_total|
---------------+-----------+------------+-------------+-----------+-----------+-----------+------------------+---------------+-----------+-------------------+
--rub          |      21422|      286961| 157131497.58|     547.57|     -90.76|   81174.54|346.17999267578125|            381|       5766|              98.26|
--kzt          |       1362|        5073|  25341198.63|    4995.31|        0.0|   26425.86|    3698.830078125|              0|          6|               1.74|


-- Пользователи с самыми высокими средними чеками
--
SELECT user_id,
    COUNT(*) AS order_count,
    ROUND(AVG(revenue::numeric), 2) AS avg_revenue,
    SUM(revenue) AS total_spent
FROM afisha.purchases
GROUP BY user_id
HAVING COUNT(*) >= 3
ORDER BY avg_revenue DESC
LIMIT 10;

--user_id        |order_count|avg_revenue|total_spent|
-----------------+-----------+-----------+-----------+
--63f33811eab908c|          4|   19819.40|   79277.58|
--caa4b28f1468b74|          5|   18498.10|   92490.51|
--4b77cc758a2de52|          4|   16516.13|   66064.65|
--c7102b05a51a255|          3|   16453.92|  49361.773|
--bd5caae300da674|          4|   15415.06|   61660.34|
--550e2a43780d281|          3|   14681.00|    44043.1|
--5b5714894bd0517|         16|   14590.96|  233455.47|
--faa6f6c2be4f1b5|          7|   13948.89|   97642.36|
--d926d7226daf556|          5|   13095.06|   65475.22|
--061b378a1519041|          4|   13083.92|   52335.68|

----Высокие средние чеки:
----Пользователь 63f33811eab908c: 4 заказа по ~19,819 в среднем.
----Пользователь 5b5714894bd0517: 16 заказов по ~14,591 (общая выручка 233,455.47).
----Возможные VIP-клиенты или ошибки (например, дублирование транзакций).


----Данные содержат значительные аномалии, которые искажают статистику. Необходима очистка и дополнительная проверка.



--1.6. Изучим период времени, за который представлены данные. 
     --Проверим, можно ли проследить влияние сезонности на данные.
--
SELECT min(created_dt_msk),
       max(created_dt_msk)
FROM afisha.purchases;

--min                    |max                    |
-------------------------+-----------------------+
--2024-06-01 00:00:00.000|2024-10-31 00:00:00.000|

----Данные охватывают весь летний период и два месяца осени 2024 года.
----Это нужно учитывать, поскольку популярность событий разного типа может меняться в зависимости от времени года. 
----Помимо этого, одна из задач проекта — исследование влияния сезонности на предпочтения пользователей.
 