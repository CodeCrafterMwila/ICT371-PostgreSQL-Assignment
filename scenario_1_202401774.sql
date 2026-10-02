-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 1: University Library Book Loans
-- Student number: 202401774

DROP TABLE IF EXISTS book_loans CASCADE;
DROP TABLE IF EXISTS books CASCADE;

-- STEP 1: Tables and data
CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL,
    loan_status    VARCHAR(10) NOT NULL DEFAULT 'BORROWED'
                   CHECK (loan_status IN ('BORROWED','RETURNED'))
);

INSERT INTO books (title, available_copies) VALUES
    ('Database Systems', 5),
    ('Discrete Mathematics', 2),
    ('Computer Networks', 1);

SELECT * FROM books ORDER BY book_id;

-- STEP 2: IF / ELSIF / ELSE stock check
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT title, available_copies FROM books ORDER BY book_id LOOP
        IF rec.available_copies = 0 THEN
            RAISE NOTICE '% : UNAVAILABLE (0 copies)', rec.title;
        ELSIF rec.available_copies <= 2 THEN
            RAISE NOTICE '% : LOW on copies (%)', rec.title, rec.available_copies;
        ELSE
            RAISE NOTICE '% : sufficiently stocked (%)', rec.title, rec.available_copies;
        END IF;
    END LOOP;
END $$;

-- STEP 3: WHILE loop and numeric FOR loop
DO $$
DECLARE
    n INT := 1;
BEGIN
    WHILE n <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number %', n;
        n := n + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number %', i;
    END LOOP;
END $$;

-- STEP 4: borrow_book procedure
CREATE OR REPLACE PROCEDURE borrow_book(p_book_id INT, p_student VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_qty;
    END IF;

    SELECT available_copies INTO v_available
    FROM books WHERE book_id = p_book_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book % does not exist', p_book_id;
    END IF;

    IF p_qty > v_available THEN
        RAISE NOTICE 'Loan REJECTED for %: requested %, only % available',
                     p_student, p_qty, v_available;
        RETURN;
    END IF;

    UPDATE books SET available_copies = available_copies - p_qty
    WHERE book_id = p_book_id;

    INSERT INTO book_loans (book_id, student_number, quantity)
    VALUES (p_book_id, p_student, p_qty);

    RAISE NOTICE 'Loan recorded for %: % copy/copies of book %', p_student, p_qty, p_book_id;
END $$;

-- STEP 5: two valid loans and one exceeding request
CALL borrow_book(1, 'S2024001', 2);   -- valid
CALL borrow_book(2, 'S2024002', 1);   -- valid
CALL borrow_book(3, 'S2024003', 4);   -- exceeds available copies (only 1)

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- STEP 6: return_book procedure
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id INT;
    v_qty     INT;
    v_status  VARCHAR(10);
BEGIN
    SELECT book_id, quantity, loan_status INTO v_book_id, v_qty, v_status
    FROM book_loans WHERE loan_id = p_loan_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Loan % does not exist', p_loan_id;
        RETURN;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned - no copies restored', p_loan_id;
        RETURN;
    END IF;

    UPDATE book_loans SET loan_status = 'RETURNED' WHERE loan_id = p_loan_id;
    UPDATE books SET available_copies = available_copies + v_qty WHERE book_id = v_book_id;

    RAISE NOTICE 'Loan % returned: % copy/copies restored', p_loan_id, v_qty;
END $$;

CALL return_book(1);   -- first call restores copies
CALL return_book(1);   -- second call must NOT restore again

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- STEP 7: explicit cursor - books with few copies remaining
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT title, available_copies FROM books
        WHERE available_copies <= 2 ORDER BY available_copies;
    v_title  books.title%TYPE;
    v_copies books.available_copies%TYPE;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_title, v_copies;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few copies left: % (%)', v_title, v_copies;
    END LOOP;
    CLOSE cur_low;
END $$;

-- STEP 8: zero copies handled with EXCEPTION block
DO $$
BEGIN
    CALL borrow_book(1, 'S2024004', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- STEP 9: final results
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;