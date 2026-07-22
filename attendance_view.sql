-- ============================================================================
-- SQL DDL Sandbox View for Student Attendance (LLM-Friendly)
-- ============================================================================
--
-- DESIGN BEST PRACTICES IMPLEMENTED FOR WREN AI / LLMs:
-- 1. Flattened Joins: Joins normalized tables (students, classes, records) to minimize model reasoning.
-- 2. Descriptive Naming: Avoids ambiguous abbreviations. Uses clear business terminology.
-- 3. Human-Readable Statuses: Translates internal raw codes (e.g., 0/1/2) into descriptive text ('Absent', 'Present', 'Excused').
-- 4. Explicit Column Comments: Uses MySQL COMMENT syntax to supply semantic context directly to Wren AI.
-- 5. Excluded Audit Fields: Leaves out system timestamps (created_at, updated_at) to avoid distracting the AI.

CREATE OR REPLACE VIEW view_student_daily_attendance AS
SELECT 
    -- 1. Student Identity Columns
    s.student_id AS student_id, -- Unique identifier
    CONCAT(s.first_name, ' ', s.last_name) AS student_full_name,
    s.grade_level AS student_grade_level, -- e.g., 'Grade 9', 'Grade 10'
    s.email AS student_email,

    -- 2. Course and Class Context
    c.course_id AS course_id,
    c.course_name AS course_name, -- e.g., 'Introduction to Computer Science'
    c.subject_area AS course_subject_area, -- e.g., 'Mathematics', 'Science', 'Technology'
    
    -- 3. Attendance Details
    a.attendance_date AS attendance_date, -- The specific date of the class
    
    -- Translate raw codes to semantic values
    CASE a.status_code
        WHEN 1 THEN 'Present'
        WHEN 0 THEN 'Absent'
        WHEN 2 THEN 'Excused Absence'
        WHEN 3 THEN 'Tardy'
        ELSE 'Unknown'
    END AS attendance_status,
    
    -- Include notes if they explain absence reasons
    a.reason_text AS absence_reason_note

FROM 
    student_attendance_records a
INNER JOIN 
    students s ON a.student_id = s.student_id
INNER JOIN 
    classes c ON a.class_id = c.class_id;

-- ============================================================================
-- End of DDL
-- ============================================================================
