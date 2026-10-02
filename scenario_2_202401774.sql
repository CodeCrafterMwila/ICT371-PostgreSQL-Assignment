-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 2: Computer Laboratory Reservations
-- Student number: 202401774

DROP TABLE IF EXISTS reservations CASCADE;
DROP TABLE IF EXISTS lab_sessions CASCADE;

-- STEP 1: Tables and data
CREATE TABLE lab_sessions (
    session_id              SERIAL PRIMARY KEY,
    session_name            VARCHAR(100) NOT NULL,
    available_workstations  INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id  SERIAL PRIMARY KEY,
    session_id      INT NOT NULL REFERENCES lab_sessions(session_id),
    lecturer        VARCHAR(100) NOT NULL,
    workstations    INT NOT NULL,
    status          VARCHAR(10) NOT NULL DEFAULT 'RESERVED'
                    CHECK (status IN ('RESERVED','CANCELLED'))
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
    ('Morning Session', 30),
    ('Afternoon Session', 12),
    ('Evening Session', 3);

SELECT * FROM lab_sessions ORDER BY session_id;

-- STEP 2: IF / ELSIF / ELSE capacity report
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT session_name, available_workstations FROM lab_sessions ORDER BY session_id LOOP
        IF rec.available_workstations = 0 THEN
            RAISE NOTICE '% : FULL', rec.session_name;
        ELSIF rec.available_workstations <= 5 THEN
            RAISE NOTICE '% : NEARLY FULL (% left)', rec.session_name, rec.available_workstations;
        ELSE
            RAISE NOTICE '% : enough workstations (%)', rec.session_name, rec.available_workstations;
        END IF;
    END LOOP;
END $$;

-- STEP 3: WHILE loop and numeric FOR loop
DO $$
DECLARE
    n INT := 1;
BEGIN
    WHILE n <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', n;
        n := n + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Workstation check number %', i;
    END LOOP;
END $$;

-- STEP 4: reserve_workstations procedure
CREATE OR REPLACE PROCEDURE reserve_workstations(p_session_id INT, p_lecturer VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: % (must be greater than zero)', p_qty;
    END IF;

    SELECT available_workstations INTO v_available
    FROM lab_sessions WHERE session_id = p_session_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist', p_session_id;
    END IF;

    IF p_qty > v_available THEN
        RAISE NOTICE 'Reservation REJECTED for %: requested %, only % available',
                     p_lecturer, p_qty, v_available;
        RETURN;
    END IF;

    UPDATE lab_sessions SET available_workstations = available_workstations - p_qty
    WHERE session_id = p_session_id;

    INSERT INTO reservations (session_id, lecturer, workstations)
    VALUES (p_session_id, p_lecturer, p_qty);

    RAISE NOTICE 'Reservation recorded for %: % workstation(s) in session %',
                 p_lecturer, p_qty, p_session_id;
END $$;

-- STEP 5: two valid reservations and one exceeding capacity
CALL reserve_workstations(1, 'Dr. Banda', 10);    -- valid
CALL reserve_workstations(2, 'Mr. Phiri', 10);    -- valid
CALL reserve_workstations(3, 'Ms. Mulenga', 8);   -- exceeds capacity (only 3)

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- STEP 6: cancel_reservation procedure
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id INT;
    v_qty        INT;
    v_status     VARCHAR(10);
BEGIN
    SELECT session_id, workstations, status INTO v_session_id, v_qty, v_status
    FROM reservations WHERE reservation_id = p_reservation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Reservation % does not exist', p_reservation_id;
        RETURN;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % already cancelled - nothing released', p_reservation_id;
        RETURN;
    END IF;

    UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
    UPDATE lab_sessions SET available_workstations = available_workstations + v_qty
    WHERE session_id = v_session_id;

    RAISE NOTICE 'Reservation % cancelled: % workstation(s) released', p_reservation_id, v_qty;
END $$;

CALL cancel_reservation(1);   -- releases workstations
CALL cancel_reservation(1);   -- second call must NOT release again

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- STEP 7: explicit cursor - sessions with few workstations remaining
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT session_name, available_workstations FROM lab_sessions
        WHERE available_workstations <= 5 ORDER BY available_workstations;
    v_name lab_sessions.session_name%TYPE;
    v_free lab_sessions.available_workstations%TYPE;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_name, v_free;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations left: % (%)', v_name, v_free;
    END LOOP;
    CLOSE cur_low;
END $$;

-- STEP 8: zero workstations handled with EXCEPTION block
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Zulu', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- STEP 9: final results
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;