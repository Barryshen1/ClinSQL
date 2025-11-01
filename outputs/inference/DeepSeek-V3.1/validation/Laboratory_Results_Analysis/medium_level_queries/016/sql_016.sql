WITH acs_patients AS (
    SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 79 AND 89
        AND (
            dd.long_title LIKE '%Unstable angina%' 
            OR dd.long_title LIKE '%STEMI%'
            OR dd.long_title LIKE '%NSTEMI%'
            OR dd.long_title LIKE '%Acute coronary syndrome%'
        )
),
first_troponin AS (
    SELECT 
        ap.subject_id,
        ap.hadm_id,
        le.charttime,
        le.valuenum AS troponin_value
    FROM acs_patients ap
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ap.hadm_id = le.hadm_id
    WHERE le.itemid = 51002  -- Troponin T
        AND le.valuenum IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ap.hadm_id ORDER BY le.charttime) = 1
),
categorized AS (
    SELECT 
        hadm_id,
        troponin_value,
        CASE 
            WHEN troponin_value <= 0.01 THEN 'Normal'
            WHEN troponin_value > 0.01 AND troponin_value <= 0.1 THEN 'Borderline'
            WHEN troponin_value > 0.1 THEN 'Elevated'
        END AS category
    FROM first_troponin
)
SELECT 
    category,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM categorized), 2) AS percentage,
    ROUND(AVG(troponin_value), 3) AS mean,
    ROUND(APPROX_QUANTILES(troponin_value, 2)[OFFSET(1)], 3) AS median,
    ROUND(APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)], 3) AS q1,
    ROUND(APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)], 3) AS q3
FROM categorized
GROUP BY category
ORDER BY category;