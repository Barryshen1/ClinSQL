WITH cohort AS (
    SELECT DISTINCT p.subject_id, a.hadm_id, i.stay_id, i.los
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.hadm_id = i.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 88 AND 98
        AND (d.icd_code LIKE '493%' OR d.icd_code LIKE 'J45%')
        AND i.los BETWEEN 1 AND 7
),
procedures_icd_count AS (
    SELECT hadm_id, COUNT(*) AS cnt
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    GROUP BY hadm_id
),
procedureevents_count AS (
    SELECT c.hadm_id, COUNT(*) AS cnt  -- Explicitly use c.hadm_id to avoid ambiguity
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
        ON c.stay_id = p.stay_id
    GROUP BY c.hadm_id
),
combined_procedures AS (
    SELECT 
        c.hadm_id, 
        c.los,
        COALESCE(pic.cnt, 0) + COALESCE(pec.cnt, 0) AS total_procedures
    FROM cohort c
    LEFT JOIN procedures_icd_count pic
        ON c.hadm_id = pic.hadm_id
    LEFT JOIN procedureevents_count pec
        ON c.hadm_id = pec.hadm_id
),
categorized AS (
    SELECT 
        hadm_id,
        total_procedures,
        CASE WHEN los BETWEEN 1 AND 3 THEN '1-3' 
             WHEN los BETWEEN 4 AND 7 THEN '4-7' 
        END AS los_category
    FROM combined_procedures
    WHERE los BETWEEN 1 AND 7
)
SELECT 
    los_category,
    APPROX_QUANTILES(total_procedures, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(total_procedures, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(total_procedures, 100)[OFFSET(75)] AS p75
FROM categorized
WHERE los_category IS NOT NULL
GROUP BY los_category
ORDER BY los_category;