-- Create a stream corresponding to the change event schema
CREATE STREAM customers_structured (
    struct_key STRUCT<id VARCHAR> KEY,
    before STRUCT<id VARCHAR, first_name VARCHAR, last_name VARCHAR, email VARCHAR, phone VARCHAR>,
    after STRUCT<id VARCHAR, first_name VARCHAR, last_name VARCHAR, email VARCHAR, phone VARCHAR>,
    op VARCHAR
) WITH (
    KAFKA_TOPIC='postgres.customers.customers',
    KEY_FORMAT='JSON_SR',
    VALUE_FORMAT='JSON_SR'
);
-- Flatten the previous structored stream to be easier to work with
CREATE STREAM customers_flattened WITH (
        KAFKA_TOPIC='customers_flattened',
        KEY_FORMAT='JSON_SR',
        VALUE_FORMAT='JSON_SR'
    ) AS SELECT
        after->id,
        after->first_name first_name, 
        after->last_name last_name,
        after->email email,
        after->phone phone
    FROM customers_structured
    PARTITION BY after->id
EMIT CHANGES;
-- Materialize the events from the flattened stream into a table
CREATE TABLE customers WITH (
        KAFKA_TOPIC='customers',
        KEY_FORMAT='JSON_SR',
        VALUE_FORMAT='JSON_SR'
    ) AS SELECT
        id,
        LATEST_BY_OFFSET(first_name) first_name, 
        LATEST_BY_OFFSET(last_name) last_name,
        LATEST_BY_OFFSET(email) email,
        LATEST_BY_OFFSET(phone) phone
    FROM customers_flattened
    GROUP BY id
EMIT CHANGES;
-- Create a stream corresponding to the change event schema
CREATE STREAM demographics_structured (
    struct_key STRUCT<id VARCHAR> KEY,
    before STRUCT<id VARCHAR, street_address VARCHAR, state VARCHAR, zip_code VARCHAR, country VARCHAR, country_code VARCHAR>,
    after STRUCT<id VARCHAR, street_address VARCHAR, state VARCHAR, zip_code VARCHAR, country VARCHAR, country_code VARCHAR>,
    op VARCHAR
) WITH (
    KAFKA_TOPIC='postgres.customers.demographics',
    KEY_FORMAT='JSON_SR',
    VALUE_FORMAT='JSON_SR'
);
-- Flatten the previous structored stream to be easier to work with
CREATE STREAM demographics_flattened WITH (
        KAFKA_TOPIC='demographics_flattened',
        KEY_FORMAT='JSON_SR',
        VALUE_FORMAT='JSON_SR'
    ) AS SELECT
        after->id,
        after->street_address,
        after->state,
        after->zip_code,
        after->country,
        after->country_code
    FROM demographics_structured
    PARTITION BY after->id
EMIT CHANGES;
-- Materialize the events from the flattened stream into a table
CREATE TABLE demographics WITH (
        KAFKA_TOPIC='demographics',
        KEY_FORMAT='JSON_SR',
        VALUE_FORMAT='JSON_SR'
    ) AS SELECT
        id, 
        LATEST_BY_OFFSET(street_address) street_address,
        LATEST_BY_OFFSET(state) state,
        LATEST_BY_OFFSET(zip_code) zip_code,
        LATEST_BY_OFFSET(country) country,
        LATEST_BY_OFFSET(country_code) country_code
    FROM demographics_flattened
    GROUP BY id
EMIT CHANGES;
-- Join the teo materializations together into one table
CREATE TABLE customers_enriched WITH (
        KAFKA_TOPIC='customers_enriched',
        KEY_FORMAT='JSON_SR',
        VALUE_FORMAT='JSON_SR'
    ) AS SELECT 
        c.id id, c.first_name first_name, c.last_name last_name, c.email email, c.phone phone,
        d.street_address street_address, d.state state, d.zip_code zip_code, d.country country, d.country_code country_code
    FROM customers c
        JOIN demographics d ON d.id = c.id
EMIT CHANGES;
-- Create a stream with a composite key
CREATE STREAM products_composite (
    struct_key STRUCT<product_id VARCHAR> KEY,
    product_id VARCHAR,
    `size` VARCHAR,
    product VARCHAR,
    department VARCHAR,
    price VARCHAR,
    __deleted VARCHAR
) WITH (
    KAFKA_TOPIC='postgres.products.products',
    KEY_FORMAT='JSON',
    VALUE_FORMAT='JSON_SR'
);
-- Re-key the stream to use a string key
CREATE STREAM products_rekeyed WITH (
        KAFKA_TOPIC='products_rekeyed',
        KEY_FORMAT='KAFKA',
        VALUE_FORMAT='JSON_SR'
    ) AS SELECT 
        product_id,
        `size`,
        product,
        department,
        price,
        __deleted deleted
    FROM products_composite
    PARTITION BY product_id
EMIT CHANGES;
-- Materialize the events from the rekeyed stream into a table
CREATE TABLE products WITH (
        KAFKA_TOPIC='products',
        KEY_FORMAT='JSON_SR',
        VALUE_FORMAT='JSON_SR'
    ) AS SELECT 
        product_id,
        LATEST_BY_OFFSET(`size`) `size`,
        LATEST_BY_OFFSET(product) product,
        LATEST_BY_OFFSET(department) department,
        LATEST_BY_OFFSET(price) price,
        LATEST_BY_OFFSET(deleted) deleted
    FROM products_rekeyed
    GROUP BY product_id
EMIT CHANGES;
-- Create a stream with a composite key
CREATE STREAM orders_composite (
    order_key STRUCT<`order_id` VARCHAR> KEY,
    order_id VARCHAR,
    product_id VARCHAR,
    customer_id VARCHAR,
    __deleted VARCHAR
) WITH (
    KAFKA_TOPIC='postgres.products.orders',
    KEY_FORMAT='JSON',
    VALUE_FORMAT='JSON_SR'
);
-- Re-key the stream to use a string key
CREATE STREAM orders_rekeyed WITH (
        KAFKA_TOPIC='orders_rekeyed',
        KEY_FORMAT='KAFKA',
        VALUE_FORMAT='JSON_SR'
    ) AS SELECT
        order_id,
        product_id,
        customer_id,
        __deleted deleted
    FROM orders_composite
    PARTITION BY order_id
EMIT CHANGES;
-- N-way join everything together to create you stream of enriched order events
CREATE STREAM orders_enriched WITH (
        KAFKA_TOPIC='orders_enriched',
        KEY_FORMAT='JSON',
        VALUE_FORMAT='JSON_SR'
    ) AS SELECT 
        o.order_id `order_id`,
        p.product_id `product_id`, p.`size` `size`, p.product `product`, p.department `department`, p.price `price`,
        c.id `id`, c.first_name `first_name`, c.last_name `last_name`, c.email `email`, c.phone `phone`,
        c.street_address `street_address`, c.state `state`, c.zip_code `zip_code`, c.country `country`, c.country_code `country_code`
    FROM orders_rekeyed o
        JOIN products p ON o.product_id = p.product_id
        JOIN customers_enriched c ON o.customer_id = c.id
    PARTITION BY o.order_id  
EMIT CHANGES;  