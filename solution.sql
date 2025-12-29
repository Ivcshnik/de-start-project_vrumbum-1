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
COPY car_shop.sales(sale_date, price, model_id, customer_id)
FROM '/Users/admin/Downloads/cars.csv'
DELIMITER ','
CSV HEADER;


-- Создание схемы и нормализованных таблиц

-- Удаление схемы если существует
DROP SCHEMA IF EXISTS car_shop CASCADE;

-- Создание схемы
CREATE SCHEMA car_shop;

-- 1. Таблица брендов
CREATE TABLE car_shop.brands (
    brand_id SERIAL PRIMARY KEY,           /* автоинкремент для уникального идентификатора */
    brand_name VARCHAR(50) NOT NULL UNIQUE, /* varchar для названий брендов с буквами и цифрами */
    country VARCHAR(50)                    /* страна происхождения, может быть NULL */
);

-- 2. Таблица моделей автомобилей
CREATE TABLE car_shop.models (
    model_id SERIAL PRIMARY KEY,           /* автоинкремент для уникального идентификатора */
    brand_id INTEGER NOT NULL REFERENCES car_shop.brands(brand_id), /* внешний ключ к бренду */
    model_name VARCHAR(50) NOT NULL,       /* название модели */
    fuel_consumption DECIMAL(5,2) CHECK (fuel_consumption > 0 OR fuel_consumption IS NULL) /* decimal для точности, NULL для электромобилей */
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
    phone VARCHAR(20),                     /* телефонный номер в разном формате */
    email VARCHAR(100),                    /* email адрес */
    discount_rate DECIMAL(5,2) DEFAULT 0 CHECK (discount_rate BETWEEN 0 AND 100) /* процент скидки 0-100 */
);

-- 5. Основная таблица продаж
CREATE TABLE car_shop.sales (
    sale_id SERIAL PRIMARY KEY,            /* автоинкремент для уникального идентификатора */
    sale_date DATE NOT NULL,               /* дата продажи */
    price DECIMAL(10,2) NOT NULL CHECK (price > 0), /* цена продажи, decimal для точности */
    model_id INTEGER NOT NULL REFERENCES car_shop.models(model_id), /* внешний ключ к модели */
    customer_id INTEGER NOT NULL REFERENCES car_shop.customers(customer_id), /* внешний ключ к клиенту */
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP /* время создания записи */
);

-- 6. Таблица связи многие-ко-многим для цветов
CREATE TABLE car_shop.sale_colors (
    sale_id INTEGER NOT NULL REFERENCES car_shop.sales(sale_id) ON DELETE CASCADE,
    color_id INTEGER NOT NULL REFERENCES car_shop.colors(color_id),
    PRIMARY KEY (sale_id, color_id)        /* составной первичный ключ */
);

-- 7. Таблица технических характеристик автомобиля
CREATE TABLE car_shop.technical_specs (
    spec_id SERIAL PRIMARY KEY,
    model_id INTEGER NOT NULL REFERENCES car_shop.models(model_id),
    fuel_consumption NUMERIC(5,2),
    engine_volume NUMERIC(3,1),
    horsepower INTEGER,
    transmission_type VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(model_id) -- одна спецификация на модель
);


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
INSERT INTO car_shop.customers (full_name, phone, discount_rate)
SELECT 
    MAX(person_name) as person_name,  -- или другая агрегирующая функция
    cleaned_phone,
    MAX(discount) as discount         -- или другая агрегирующая функция
FROM (
    SELECT 
        person_name,
        CASE 
            WHEN phone LIKE '%x%' THEN SPLIT_PART(phone, 'x', 1) -- извлекаем номера телефонов из
            													 -- записей вида 037-001-9765x6148	
            ELSE phone 
        END as cleaned_phone,
        discount
    FROM raw_data.sales
) as cleaned_data
GROUP BY cleaned_phone
ON CONFLICT (phone) DO UPDATE SET
discount_rate = EXCLUDED.discount_rate;

-- 3. Приводим все номера к виду ХХХ-ХХХ-ХХХХ через использования условий и регулярных выражений
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

-- 4. Заполняем таблицу брендов
INSERT INTO car_shop.brands (brand_name, country)
SELECT DISTINCT 
    CASE 
        WHEN SPLIT_PART(auto, ',', 1) = 'Tesla Model X' THEN 'Tesla'
        WHEN SPLIT_PART(auto, ',', 1) = 'Tesla Model Y' THEN 'Tesla'
        WHEN SPLIT_PART(auto, ',', 1) = 'Tesla Model 3' THEN 'Tesla'
        WHEN SPLIT_PART(auto, ',', 1) = 'Tesla Model S' THEN 'Tesla'
        ELSE TRIM(SPLIT_PART(SPLIT_PART(auto, ',', 1), ' ', 1))
    END AS brand_name,
    brand_origin
FROM raw_data.sales
WHERE brand_origin IS NOT NULL
ON CONFLICT (brand_name) DO NOTHING;

-- Добавляем бренды с NULL страной происхождения
INSERT INTO car_shop.brands (brand_name, country)
SELECT DISTINCT 
    CASE 
        WHEN SPLIT_PART(auto, ',', 1) = 'Tesla Model X' THEN 'Tesla'
        WHEN SPLIT_PART(auto, ',', 1) = 'Tesla Model Y' THEN 'Tesla'
        WHEN SPLIT_PART(auto, ',', 1) = 'Tesla Model 3' THEN 'Tesla'
        WHEN SPLIT_PART(auto, ',', 1) = 'Tesla Model S' THEN 'Tesla'
        ELSE TRIM(SPLIT_PART(SPLIT_PART(auto, ',', 1), ' ', 1))
    END AS brand_name,
    NULL
FROM raw_data.sales
WHERE brand_origin IS NULL
ON CONFLICT (brand_name) DO NOTHING;

-- 5. Заполняем таблицу технических характеристик из сырых данных
INSERT INTO car_shop.technical_specs (model_id, fuel_consumption)
SELECT DISTINCT ON (m.model_id)
    m.model_id,
    CASE 
        WHEN rs.gasoline_consumption = 0 THEN NULL
        ELSE rs.gasoline_consumption
    END AS fuel_consumption
FROM raw_data.sales rs
JOIN car_shop.brands b ON b.brand_name = 
    CASE 
        WHEN SPLIT_PART(rs.auto, ',', 1) = 'Tesla Model X' THEN 'Tesla'
        WHEN SPLIT_PART(rs.auto, ',', 1) = 'Tesla Model Y' THEN 'Tesla'
        WHEN SPLIT_PART(rs.auto, ',', 1) = 'Tesla Model 3' THEN 'Tesla'
        WHEN SPLIT_PART(rs.auto, ',', 1) = 'Tesla Model S' THEN 'Tesla'
        ELSE TRIM(SPLIT_PART(SPLIT_PART(rs.auto, ',', 1), ' ', 1))
    END
JOIN car_shop.models m ON m.brand_id = b.brand_id 
    AND m.model_name = CASE 
        WHEN SPLIT_PART(rs.auto, ',', 1) LIKE '%Tesla Model%' THEN
            TRIM(SPLIT_PART(SPLIT_PART(rs.auto, ',', 1), ' ', 2) || ' ' || 
                 SPLIT_PART(SPLIT_PART(rs.auto, ',', 1), ' ', 3))
        ELSE
            TRIM(SUBSTRING(SPLIT_PART(rs.auto, ',', 1) FROM POSITION(' ' IN SPLIT_PART(rs.auto, ',', 1)) + 1))
    END
ORDER BY m.model_id, rs.gasoline_consumption DESC -- выбираем наибольшее значение
ON CONFLICT (model_id) DO UPDATE SET
    fuel_consumption = EXCLUDED.fuel_consumption,
    updated_at = CURRENT_TIMESTAMP;

-- 6. Заполняем таблицу продаж
INSERT INTO car_shop.sales (sale_date, price, model_id, customer_id)
SELECT 
    rs.date,
    rs.price,
    m.model_id,
    c.customer_id
FROM raw_data.sales rs
JOIN car_shop.brands b ON b.brand_name = 
    CASE 
        WHEN SPLIT_PART(rs.auto, ',', 1) = 'Tesla Model X' THEN 'Tesla'
        WHEN SPLIT_PART(rs.auto, ',', 1) = 'Tesla Model Y' THEN 'Tesla'
        WHEN SPLIT_PART(rs.auto, ',', 1) = 'Tesla Model 3' THEN 'Tesla'
        WHEN SPLIT_PART(rs.auto, ',', 1) = 'Tesla Model S' THEN 'Tesla'
        ELSE TRIM(SPLIT_PART(SPLIT_PART(rs.auto, ',', 1), ' ', 1))
    END
JOIN car_shop.models m ON m.brand_id = b.brand_id 
    AND m.model_name = 
        CASE 
            WHEN SPLIT_PART(rs.auto, ',', 1) LIKE '%Tesla Model%' THEN
                TRIM(SPLIT_PART(SPLIT_PART(rs.auto, ',', 1), ' ', 2) || ' ' || 
                     SPLIT_PART(SPLIT_PART(rs.auto, ',', 1), ' ', 3))
            ELSE
                TRIM(SUBSTRING(SPLIT_PART(rs.auto, ',', 1) FROM POSITION(' ' IN SPLIT_PART(rs.auto, ',', 1)) + 1))
        END
JOIN car_shop.customers c ON c.phone = rs.phone;
    
 -- 7. Заполняем таблицу связи цветов
INSERT INTO car_shop.sale_colors (sale_id, color_id)
SELECT 
    s.sale_id,
    col.color_id
FROM car_shop.sales s
JOIN raw_data.sales rs ON s.sale_date = rs.date AND s.price = rs.price
JOIN car_shop.customers c ON s.customer_id = c.customer_id AND c.phone = rs.phone
JOIN car_shop.colors col ON col.color_name = TRIM(SPLIT_PART(rs.auto, ',', 2))
ON CONFLICT (sale_id, color_id) DO NOTHING; 



-- Этап 2. Создание выборок

---- Задание 1. Напишите запрос, который выведет процент моделей машин, у которых нет параметра `gasoline_consumption`.
SELECT 
    ROUND(
        COUNT(*) FILTER (WHERE ts.fuel_consumption IS NULL) * 100.0 / 
        NULLIF(COUNT(m.model_id), 0), 
        2
    ) AS nulls_percentage_gasoline_consumption
FROM car_shop.models m
LEFT JOIN car_shop.technical_specs ts ON m.model_id = ts.model_id;


---- Задание 2. Напишите запрос, который покажет название бренда и среднюю цену его автомобилей в разбивке по всем годам с учётом скидки.
SELECT 
    b.brand_name,
    EXTRACT(YEAR FROM s.sale_date) AS year,
    ROUND(
        AVG(
            s.price * (1 - COALESCE(c.discount_rate, 0) / 100.0)
        ), 
        2
    ) AS price_avg
FROM car_shop.sales s
JOIN car_shop.models m ON s.model_id = m.model_id
JOIN car_shop.brands b ON m.brand_id = b.brand_id
LEFT JOIN car_shop.customers c ON s.customer_id = c.customer_id
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
            s.price * (1 - COALESCE(c.discount_rate, 0) / 100.0)
        ), 
        2
    ) AS price_avg
FROM car_shop.sales s
LEFT JOIN car_shop.customers c ON s.customer_id = c.customer_id
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
    b.country AS brand_origin,
    MAX(s.price / (1 - c.discount_rate)) AS price_max,
    ROUND(ABS(MIN(s.price / (1 - c.discount_rate))), 2) AS price_min
FROM car_shop.sales s
JOIN car_shop.models m ON s.model_id = m.model_id
JOIN car_shop.brands b ON m.brand_id = b.brand_id
JOIN car_shop.customers c ON c.customer_id = s.customer_id 
GROUP BY b.country
ORDER BY b.country;


---- Задание 6. Напишите запрос, который покажет количество всех пользователей из США. Это пользователи, у которых номер телефона начинается на +1.

SELECT 
    COUNT(*) AS persons_from_usa_count
FROM car_shop.customers
WHERE phone LIKE '+1%';


