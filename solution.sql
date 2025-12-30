-- Этап 1. Создание и заполнение БД

-- Создание схемы raw_data, если не существует
CREATE SCHEMA IF NOT EXISTS raw_data;


-- Создание таблицы sales в схеме raw_data
CREATE TABLE raw_data.sales (
    id SERIAL PRIMARY KEY,
    auto VARCHAR(100),
    gasoline_consumption DECIMAL(5,2),
    price DECIMAL(10,2),
    date DATE,
    person_name VARCHAR(100),
    phone TEXT,
    discount DECIMAL(5,2) DEFAULT 0,
    brand_origin VARCHAR(50)
);


-- Заполнение таблицы сырыми данными
COPY raw_data.sales(id, auto, gasoline_consumption, price, date, person_name, phone, discount, brand_origin)
FROM '/Users/admin/Downloads/cars.csv'
DELIMITER ','
CSV HEADER
NULL 'null';
/* Загрузил тестовый запрос. Дико извиняюсь! */

-- Создание схемы и нормализованных таблиц

-- Удаление схемы если существует
DROP SCHEMA IF EXISTS car_shop CASCADE;

-- Создание схемы
CREATE SCHEMA car_shop;

-- 0. Создание таблицы стран
CREATE TABLE car_shop.countries (
    country_id SERIAL PRIMARY KEY,          /* автоинкрементный первичный ключ */
    country_name VARCHAR(100) UNIQUE, /* уникальное название страны */
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- 1. Таблица брендов
CREATE TABLE car_shop.brands (
    brand_id SERIAL PRIMARY KEY,           /* автоинкремент для уникального идентификатора */
    brand_name VARCHAR(50) NOT NULL UNIQUE, /* varchar для названий брендов с буквами и цифрами */
    country_id INTEGER REFERENCES car_shop.countries(country_id) ON DELETE SET NULL /* внешний ключ к стране */
);

-- 2. Таблица моделей автомобилей
CREATE TABLE car_shop.models (
    model_id SERIAL PRIMARY KEY,           /* автоинкремент для уникального идентификатора */
    brand_id INTEGER NOT NULL REFERENCES car_shop.brands(brand_id), /* внешний ключ к бренду */
    model_name VARCHAR(100) NOT NULL,       /* название модели */
    fuel_consumption DECIMAL(5,2) CHECK (fuel_consumption > 0 OR fuel_consumption IS NULL) /* decimal для точности, NULL для электромобилей */
    UNIQUE(brand_id, model_name)  -- составное уникальное ограничение
);

-- 3. Таблица цветов
CREATE TABLE car_shop.colors (
    color_id SERIAL PRIMARY KEY,           /* автоинкремент для уникального идентификатора */
    color_name VARCHAR(20) NOT NULL UNIQUE /* название цвета, уникальное */
);

-- 4. Таблица клиентов
CREATE TABLE car_shop.customers (
    customer_id SERIAL PRIMARY KEY,        /* автоинкремент для уникального идентификатора */
    full_name VARCHAR(100) NOT NULL,       /* полное имя клиента */
    phone VARCHAR(20) UNIQUE                     /* телефонный номер в разном формате */
);

-- 5. Основная таблица продаж
CREATE TABLE car_shop.sales (
    sale_id SERIAL PRIMARY KEY,            /* автоинкремент для уникального идентификатора */
    sale_date DATE NOT NULL,               /* дата продажи */
    price DECIMAL(10,2) NOT NULL CHECK (price > 0), /* цена продажи, decimal для точности */
    model_id INTEGER REFERENCES car_shop.models(model_id), /* внешний ключ к модели */
    customer_id INTEGER REFERENCES car_shop.customers(customer_id), /* внешний ключ к клиенту */
    discount_rate DECIMAL(5,2) DEFAULT 0 CHECK (discount_rate BETWEEN 0 AND 100), /* процент скидки 0-100 */
    model_color_id INTEGER REFERENCES car_shop.colors(color_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP /* время создания записи */
);

-- Добавляем столбец model_color_id в car_shop.sales
ALTER TABLE car_shop.sales 
ADD COLUMN model_color_id INTEGER 
REFERENCES car_shop.colors(color_id);


-- Индексы для оптимизации производительности
CREATE INDEX idx_sales_date ON car_shop.sales(sale_date);
CREATE INDEX idx_sales_customer ON car_shop.sales(customer_id);
CREATE INDEX idx_sales_model ON car_shop.sales(model_id);
CREATE INDEX idx_models_brand ON car_shop.models(brand_id);



-- Заполнение таблиц данными из сырой таблицы

-- 1. Заполняем таблицу цветов
INSERT INTO car_shop.colors (color_name)
SELECT DISTINCT TRIM(SPLIT_PART(auto, ',', 2)) AS color_name
FROM raw_data.sales
ON CONFLICT (color_name) DO NOTHING;

-- 2. Заполняем таблицу клиентов
-- Сначала группируем данные с помощью GROUP BY для удаления дубликатов
INSERT INTO car_shop.customers (full_name, phone)
SELECT 
    MAX(person_name) as person_name,
    cleaned_phone
FROM (
    SELECT 
        person_name,
        CASE 
            WHEN phone LIKE '%x%' THEN SPLIT_PART(phone, 'x', 1) -- извлекаем номера телефонов
            ELSE phone 
        END as cleaned_phone
    FROM raw_data.sales
) as cleaned_data
GROUP BY cleaned_phone
ON CONFLICT (phone) DO UPDATE SET
    full_name = EXCLUDED.full_name;

-- 3. Заполняем таблицу стран из сырых данных
INSERT INTO car_shop.countries (country_name)
SELECT DISTINCT brand_origin
FROM raw_data.sales
ORDER BY brand_origin
ON CONFLICT (country_name) DO NOTHING;

-- 4. Заполняем таблицу брендов (с LEFT JOIN)
INSERT INTO car_shop.brands (brand_name, country_id)
SELECT DISTINCT 
    TRIM(split_part(s.auto, ' ', 1)) AS brand_name,
    c.country_id 
FROM raw_data.sales s 
LEFT JOIN car_shop.countries c ON c.country_name = s.brand_origin
WHERE TRIM(split_part(s.auto, ' ', 1)) != ''
ON CONFLICT (brand_name) DO UPDATE SET
    country_id = EXCLUDED.country_id;


-- 5. Заполняем таблицу моделей
INSERT INTO car_shop.models (brand_id, model_name, fuel_consumption)
SELECT DISTINCT 
    b.brand_id,
    trim(substring(split_part(rs.auto, ',', 1) FROM position(' ' IN auto))) AS model,
    CASE 
        WHEN gasoline_consumption = 0 THEN NULL
        ELSE gasoline_consumption
    END AS fuel_consumption
FROM raw_data.sales rs
JOIN car_shop.brands b ON b.brand_name = split_part(rs.auto, ' ', 1)
ON CONFLICT (brand_id, model_name) DO NOTHING;

-- Приводим все номера к виду ХХХ-ХХХ-ХХХХ через использования условий и регулярных выражений
/*UPDATE car_shop.customers
SET phone = 
    CASE 
        WHEN LENGTH(REGEXP_REPLACE(phone, '[^0-9]', '', 'g')) >= 10
        THEN SUBSTRING(
            REGEXP_REPLACE(phone, '[^0-9]', '', 'g') 
            FROM LENGTH(REGEXP_REPLACE(phone, '[^0-9]', '', 'g')) - 9
            FOR 3
        ) || '-' ||
        SUBSTRING(
            REGEXP_REPLACE(phone, '[^0-9]', '', 'g')
            FROM LENGTH(REGEXP_REPLACE(phone, '[^0-9]', '', 'g')) - 6
            FOR 3
        ) || '-' ||
        SUBSTRING(
            REGEXP_REPLACE(phone, '[^0-9]', '', 'g')
            FROM LENGTH(REGEXP_REPLACE(phone, '[^0-9]', '', 'g')) - 3
            FOR 4
        )
        ELSE phone
    END
WHERE phone IS NOT NULL; */
-- Пункт 3 полностью рабочий, но как оказалось по последнему
-- заданию не очень нужный, а я потратил на него больше всего времени (((



-- 6. Заполняем таблицу продаж
/* Проблема возникала из-за того, что при создании таблиц использовалось ограницение NOT NULL 
для полей model_id, customer_id, model_color_id */
INSERT INTO car_shop.sales (sale_date, price, model_id, customer_id, discount_rate, model_color_id)
SELECT 
    rs.date,
    rs.price,
    m.model_id,
    c.customer_id,
    rs.discount,
    col.color_id 
FROM raw_data.sales rs
LEFT JOIN car_shop.models m ON m.model_name = TRIM(SUBSTRING(SPLIT_PART(rs.auto, ',', 1) FROM POSITION(' ' IN rs.auto) + 1))
LEFT JOIN car_shop.customers c ON c.phone = rs.phone
LEFT JOIN car_shop.colors col ON col.color_name = TRIM(SPLIT_PART(rs.auto, ',', 2))
WHERE rs.date IS NOT NULL
  AND rs.price IS NOT NULL
  AND rs.price > 0;
    



-- Этап 2. Создание выборок

---- Задание 1. Напишите запрос, который выведет процент моделей машин, у которых нет параметра `gasoline_consumption`.
SELECT 
    ROUND(
        COUNT(*) FILTER (WHERE m.fuel_consumption IS NULL) * 100.0 / 
        NULLIF(COUNT(m.model_id), 0), 
        2
    ) AS nulls_percentage_gasoline_consumption
FROM car_shop.models m


---- Задание 2. Напишите запрос, который покажет название бренда и среднюю цену его автомобилей в разбивке по всем годам с учётом скидки.
SELECT 
    b.brand_name,
    EXTRACT(YEAR FROM s.sale_date) AS year,
    ROUND(
        AVG(
            s.price * (1 - COALESCE(s.discount_rate, 0) / 100.0)
        ), 
        2
    ) AS price_avg
FROM car_shop.sales s
JOIN car_shop.models m ON s.model_id = m.model_id
JOIN car_shop.brands b ON m.brand_id = b.brand_id
WHERE s.sale_date IS NOT NULL
  AND s.price IS NOT NULL
GROUP BY b.brand_name, EXTRACT(YEAR FROM s.sale_date)
ORDER BY b.brand_name ASC, year ASC;


---- Задание 3. Посчитайте среднюю цену всех автомобилей с разбивкой по месяцам в 2022 году с учётом скидки.
SELECT 
    EXTRACT(MONTH FROM s.sale_date)::INTEGER AS month,
    2022 AS year,
    ROUND(
        AVG(
            s.price * (1 - COALESCE(s.discount_rate, 0) / 100.0)
        ), 
        2
    ) AS price_avg
FROM car_shop.sales s
WHERE EXTRACT(YEAR FROM s.sale_date) = 2022
  AND s.sale_date IS NOT NULL
  AND s.price IS NOT NULL
GROUP BY EXTRACT(MONTH FROM s.sale_date)
ORDER BY EXTRACT(MONTH FROM s.sale_date) ASC;


---- Задание 4. Напишите запрос, который выведет список купленных машин у каждого пользователя.
SELECT 
    c.full_name AS person,
    STRING_AGG(b.brand_name || ' ' || m.model_name, ', ') AS cars
FROM car_shop.sales s
JOIN car_shop.models m ON s.model_id = m.model_id
JOIN car_shop.brands b ON m.brand_id = b.brand_id
JOIN car_shop.customers c ON s.customer_id = c.customer_id
GROUP BY c.full_name
ORDER BY c.full_name ASC;


---- Задание 5. Напишите запрос, который вернёт самую большую и самую маленькую цену продажи автомобиля с разбивкой по стране без учёта скидки. Цена в колонке price дана с учётом скидки.
SELECT 
    c.country_name AS brand_origin,
    MAX(s.price / (1 - NULLIF(s.discount_rate, 0)/100)) AS price_max,
    ROUND(MIN(s.price / (1 - NULLIF(s.discount_rate, 0)/100)), 2) AS price_min   
FROM car_shop.sales s
JOIN car_shop.models m ON s.model_id = m.model_id
JOIN car_shop.brands b ON m.brand_id = b.brand_id
JOIN car_shop.countries c ON c.country_id  = b.country_id
GROUP BY c.country_name 
ORDER BY c.country_name;


---- Задание 6. Напишите запрос, который покажет количество всех пользователей из США. Это пользователи, у которых номер телефона начинается на +1.
SELECT 
    COUNT(*) AS persons_from_usa_count
FROM car_shop.customers
WHERE phone LIKE '+1%';


