WITH cohort AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        p.anchor_age,
        p.anchor_year,
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
        CASE WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = a.hadm_id
              AND (
                (d.icd_version = 9 AND d.icd_code LIKE '410%')
                OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
              )
        ) THEN 1 ELSE 0 END AS has_mi
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
    WHERE p.gender = 'F'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 89 AND 99
),
temp_data AS (
    SELECT
        c.subject_id,
        c.valuenum,
        CASE
            WHEN c.valuenum < 36 THEN '<36'
            WHEN c.valuenum >= 36 AND c.valuenum < 38 THEN '36-37.9'
            ELSE '≥38'
        END AS temp_category,
        co.has_mi
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    JOIN cohort co ON c.subject_id = co.subject_id AND c.hadm_id = co.hadm_id
    WHERE c.itemid = 223761
      AND c.valuenum IS NOT NULL
)
SELECT
    temp_category,
    AVG(valuenum) AS mean,
    PERCENTILE_CONT(valuenum, 0.5) WITHIN GROUP (ORDER BY valuenum) AS median,
    PERCENTILE_CONT(valuenum, 0.75) WITHIN GROUP (ORDER BY valuenum) - PERCENTILE_CONT(valuenum, 0.25) WITHIN GROUP (ORDER BY valuenum) AS iqr,
    COUNT(DISTINCT subject_id) AS unique_patients,
    COUNT(*) AS measurement_count,
    COUNT(DISTINCT CASE WHEN has_mi = 1 THEN subject_id END) / COUNT(DISTINCT subject_id) AS mi_rate
FROM temp_data
GROUP BY temp_category;