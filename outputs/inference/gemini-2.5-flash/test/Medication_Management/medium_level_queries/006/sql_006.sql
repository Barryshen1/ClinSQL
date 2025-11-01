WITH cohort AS (
    -- Step 1: Identify the target patient cohort
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 48 AND 58
        -- Check for Type 2 Diabetes Mellitus (ICD-10: E11.x)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd_t2dm
            WHERE
                dicd_t2dm.hadm_id = ad.hadm_id
                AND dicd_t2dm.icd_version = 10
                AND dicd_t2dm.icd_code LIKE 'E11%'
        )
        -- Check for Heart Failure (ICD-10: I50.x)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd_hf
            WHERE
                dicd_hf.hadm_id = ad.hadm_id
                AND dicd_hf.icd_version = 10
                AND dicd_hf.icd_code LIKE 'I50%'
        )
),
glp1_initiations AS (
    -- Step 2: Identify the first injectable GLP-1 prescription time for each eligible admission
    SELECT
        c.hadm_id,
        MIN(p.starttime) AS first_glp1_starttime
    FROM
        cohort c
    JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
    WHERE
        (
            -- List of common injectable GLP-1 receptor agonists (case-insensitive)
            LOWER(p.drug) LIKE LOWER('%exenatide%') OR
            LOWER(p.drug) LIKE LOWER('%liraglutide%') OR
            LOWER(p.drug) LIKE LOWER('%dulaglutide%') OR
            LOWER(p.drug) LIKE LOWER('%semaglutide%') OR -- Semaglutide (Ozempic/Wegovy) is injectable
            LOWER(p.drug) LIKE LOWER('%lixisenatide%') OR
            LOWER(p.drug) LIKE LOWER('%albiglutide%') -- Though discontinued, may appear in older records
        )
        AND p.route IN ('SC', 'IV') -- Filter for injectable routes (Subcutaneous, Intravenous)
    GROUP BY
        c.hadm_id
)
-- Step 3 & 4: Calculate initiation rates and absolute difference
SELECT
    COUNT(DISTINCT c.hadm_id) AS total_eligible_admissions,
    COUNT(DISTINCT CASE
        WHEN gi.first_glp1_starttime IS NOT NULL
             AND gi.first_glp1_starttime <= DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
        THEN c.hadm_id
    END) AS initiated_first_72h_count,
    COUNT(DISTINCT CASE
        WHEN gi.first_glp1_starttime IS NOT NULL
             AND gi.first_glp1_starttime >= DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR)
        THEN c.hadm_id
    END) AS initiated_last_48h_count,
    ROUND(
        (COUNT(DISTINCT CASE
            WHEN gi.first_glp1_starttime IS NOT NULL
                 AND gi.first_glp1_starttime <= DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
            THEN c.hadm_id
        END) * 100.0) / COUNT(DISTINCT c.hadm_id), 2
    ) AS rate_first_72h_pct,
    ROUND(
        (COUNT(DISTINCT CASE
            WHEN gi.first_glp1_starttime IS NOT NULL
                 AND gi.first_glp1_starttime >= DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR)
            THEN c.hadm_id
        END) * 100.0) / COUNT(DISTINCT c.hadm_id), 2
    ) AS rate_last_48h_pct,
    ROUND(
        (
            (COUNT(DISTINCT CASE
                WHEN gi.first_glp1_starttime IS NOT NULL
                     AND gi.first_glp1_starttime <= DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
                THEN c.hadm_id
            END) * 100.0) / COUNT(DISTINCT c.hadm_id)
        ) - (
            (COUNT(DISTINCT CASE
                WHEN gi.first_glp1_starttime IS NOT NULL
                     AND gi.first_glp1_starttime >= DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR)
                THEN c.hadm_id
            END) * 100.0) / COUNT(DISTINCT c.hadm_id)
        ), 2
    ) AS absolute_difference_pp
FROM
    cohort c
LEFT JOIN
    glp1_initiations gi
    ON c.hadm_id = gi.hadm_id;