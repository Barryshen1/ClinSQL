WITH admissions_filtered AS (
    SELECT 
        a.hadm_id,
        a.admission_type,
        -- Compute age at admission
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
        -- Compute LOS in days (fractional)
        TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
        -- Filter age: 73 to 83 inclusive
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 73 AND 83
        -- Filter admission type to only 'EMERGENCY' and 'ELECTIVE'
        AND a.admission_type IN ('EMERGENCY', 'ELECTIVE')
        -- Filter for LOS in the required ranges
        AND (
            (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) BETWEEN 1 AND 3)
            OR 
            (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) BETWEEN 4 AND 7)
        )
),
-- Identify ultrasound procedures
ultrasound_procs AS (
    SELECT 
        h.hadm_id,
        h.hcpcs_cd
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
        ON h.hcpcs_cd = d.code
    WHERE LOWER(d.long_description) LIKE '%ultrasound%'
        OR LOWER(d.long_description) LIKE '%echo%'
),
-- For each admission, count the number of ultrasound procedures
admission_ultrasound_count AS (
    SELECT 
        a.hadm_id,
        COUNT(u.hcpcs_cd) AS ultrasound_count
    FROM admissions_filtered a
    LEFT JOIN ultrasound_procs u
        ON a.hadm_id = u.hadm_id
    GROUP BY a.hadm_id
),
-- Prepare final data with grouping variables
final_data AS (
    SELECT 
        a.hadm_id,
        a.admission_type,
        a.los_days,
        u.ultrasound_count,
        -- Define LOS group
        CASE 
            WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3'
            WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7'
        END AS los_group,
        -- Define admission type group
        CASE 
            WHEN a.admission_type = 'EMERGENCY' THEN 'ED'
            WHEN a.admission_type = 'ELECTIVE' THEN 'Elective'
        END AS admission_type_group
    FROM admissions_filtered a
    LEFT JOIN admission_ultrasound_count u
        ON a.hadm_id = u.hadm_id
)
-- Calculate statistics
SELECT 
    los_group,
    admission_type_group,
    AVG(ultrasound_count) AS mean_ultrasounds,
    MIN(ultrasound_count) AS min_ultrasounds,
    MAX(ultrasound_count) AS max_ultrasounds
FROM final_data
GROUP BY los_group, admission_type_group
ORDER BY los_group, admission_type_group;