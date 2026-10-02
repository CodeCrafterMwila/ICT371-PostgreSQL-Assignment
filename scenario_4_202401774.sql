-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 4: Campus Clinic Medicine Dispensing
-- Student number: 202401774

DROP TABLE IF EXISTS dispensing_records CASCADE;
DROP TABLE IF EXISTS medicines CASCADE;

-- STEP 1: Tables and data
CREATE TABLE medicines (
    medicine_id    SERIAL PRIMARY KEY,
    medicine_name  VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    record_id      SERIAL PRIMARY KEY,
    medicine_id    INT NOT NULL REFERENCES medicines(medicine_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL,
    status         VARCHAR(10) NOT NULL DEFAULT 'DISPENSED'
                   CHECK (status IN ('DISPENSED','REVERSED'))
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
    ('Paracetamol', 100),
    ('Amoxicillin', 15),
    ('Cough Syrup', 4);

SELECT * FROM medicines ORDER BY medicine_id;

-- STEP 2: IF / ELSIF / ELSE stock report (low-stock threshold = 20)
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT medicine_name, stock_quantity FROM medicines ORDER BY medicine_id LOOP
        IF rec.stock_quantity = 0 THEN
            RAISE NOTICE '% : OUT OF STOCK', rec.medicine_name;
        ELSIF rec.stock_quantity < 20 THEN
            RAISE NOTICE '% : LOW on stock (%)', rec.medicine_name, rec.stock_quantity;
        ELSE
            RAISE NOTICE '% : sufficiently stocked (%)', rec.medicine_name, rec.stock_quantity;
        END IF;
    END LOOP;
END $$;

-- STEP 3: WHILE loop and numeric FOR loop
DO $$
DECLARE
    n INT := 1;
BEGIN
    WHILE n <= 3 LOOP
        RAISE NOTICE 'Stock review day %', n;
        n := n + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection number %', i;
    END LOOP;
END $$;

-- STEP 4: dispense_medicine procedure
CREATE OR REPLACE PROCEDURE dispense_medicine(p_medicine_id INT, p_student VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_qty;
    END IF;

    SELECT stock_quantity INTO v_stock
    FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine % does not exist', p_medicine_id;
    END IF;

    IF p_qty > v_stock THEN
        RAISE NOTICE 'Dispensing REJECTED for %: requested %, only % in stock',
                     p_student, p_qty, v_stock;
        RETURN;
    END IF;

    UPDATE medicines SET stock_quantity = stock_quantity - p_qty
    WHERE medicine_id = p_medicine_id;

    INSERT INTO dispensing_records (medicine_id, student_number, quantity)
    VALUES (p_medicine_id, p_student, p_qty);

    RAISE NOTICE 'Dispensed % unit(s) of medicine % to %', p_qty, p_medicine_id, p_student;
END $$;

-- STEP 5: two valid quantities and one exceeding stock
CALL dispense_medicine(1, 'S2024001', 10);   -- valid
CALL dispense_medicine(2, 'S2024002', 5);    -- valid
CALL dispense_medicine(3, 'S2024003', 9);    -- exceeds stock (only 4)

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- STEP 6: reverse_dispensing procedure
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_medicine_id INT;
    v_qty         INT;
    v_status      VARCHAR(10);
BEGIN
    SELECT medicine_id, quantity, status INTO v_medicine_id, v_qty, v_status
    FROM dispensing_records WHERE record_id = p_record_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Dispensing record % does not exist', p_record_id;
        RETURN;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % already reversed - stock not restored again', p_record_id;
        RETURN;
    END IF;

    UPDATE dispensing_records SET status = 'REVERSED' WHERE record_id = p_record_id;
    UPDATE medicines SET stock_quantity = stock_quantity + v_qty WHERE medicine_id = v_medicine_id;

    RAISE NOTICE 'Record % reversed: % unit(s) restored to stock', p_record_id, v_qty;
END $$;

CALL reverse_dispensing(1);   -- restores stock
CALL reverse_dispensing(1);   -- second call must NOT restore again

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- STEP 7: explicit (parameterised) cursor - medicines below threshold
DO $$
DECLARE
    cur_low CURSOR (p_threshold INT) FOR
        SELECT medicine_name, stock_quantity FROM medicines
        WHERE stock_quantity < p_threshold ORDER BY stock_quantity;
    v_name  medicines.medicine_name%TYPE;
    v_stock medicines.stock_quantity%TYPE;
BEGIN
    OPEN cur_low(20);
    LOOP
        FETCH cur_low INTO v_name, v_stock;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Below threshold (20): % (%)', v_name, v_stock;
    END LOOP;
    CLOSE cur_low;
END $$;

-- STEP 8: negative quantity handled with EXCEPTION block
DO $$
BEGIN
    CALL dispense_medicine(1, 'S2024004', -5);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- STEP 9: final results
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;