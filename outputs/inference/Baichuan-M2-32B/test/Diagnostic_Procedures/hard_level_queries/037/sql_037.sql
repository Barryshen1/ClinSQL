WITH eligible_patients AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_year - p.anchor_age AS birth_year,
        a.hadm_id,
        a.admittime,
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp`.patients p
    JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a 
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
        AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 53 AND 63
),
icu_stays AS (
    SELECT 
        subject_id,
        hadm_id,
        intime,
        outtime,
        TIMESTAMP_DIFF(outtime, intime, DAY) AS los_days,
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu`.icustays
    WHERE subject_id IN (SELECT subject_id FROM eligible_patients)
),
first_icu_stays AS (
    SELECT 
        subject_id,
        hadm_id,
        intime,
        outtime,
        los_days
    FROM icu_stays
    WHERE rn = 1
),
sepsis_diagnoses AS (
    SELECT 
        d.hadm_id,
        MAX(CASE WHEN d.icd_code IN (
            'A40', 'A41', 'R65.20', 'R65.21', 'R65.22', 'R65.23', 'R65.24', 'R65.25', 
            'R65.26', 'R65.27', 'R65.28', 'R65.29', 'R65.81', 'R65.82', 'R65.83', 
            'R65.84', 'R65.85', 'R65.86', 'R65.87', 'R65.88', 'R65.89', 'R65.9'
        ) AND d.icd_version = 10 THEN 1 ELSE 0 END) AS sepsis_flag
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    WHERE d.hadm_id IN (SELECT hadm_id FROM first_icu_stays)
        AND d.icd_version = 10
    GROUP BY d.hadm_id
),
procedures_count AS (
    SELECT 
        f.subject_id,
        f.hadm_id,
        COUNT(*) AS procedure_count  -- Fixed: Count rows instead of non-existent column
    FROM first_icu_stays f
    LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents p 
        ON f.subject_id = p.subject_id 
        AND f.hadm_id = p.hadm_id 
        AND p.starttime BETWEEN f.intime AND f.intime + INTERVAL 24 HOUR
    GROUP BY f.subject_id, f.hadm_id
),
admissions_info AS (
    SELECT 
        a.hadm_id,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
    WHERE a.hadm_id IN (SELECT hadm_id FROM first_icu_stays)
),
all_data AS (
    SELECT 
        f.subject_id,
        f.hadm_id,
        f.los_days,
        a.hospital_expire_flag,
        s.sepsis_flag,
        p.procedure_count
    FROM first_icu_stays f
    JOIN admissions_info a ON f.hadm_id = a.hadm_id
    JOIN sepsis_diagnoses s ON f.hadm_id = s.hadm_id
    JOIN procedures_count p ON f.hadm_id = p.hadm_id
),
sepsis_pcts AS (
    SELECT 
        APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS p75,
        APPROX_QUANTILES(procedure_count, 100)[OFFSET(90)] AS p90
    FROM all_data
    WHERE sepsis_flag = 1
),
group_metrics AS (
    SELECT 
        sepsis_flag,
        AVG(los_days) AS avg_los,
        AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality
    FROM all_data
    GROUP BY sepsis_flag
)
SELECT 
    'sepsis' AS group_type,
    p75 AS percentile_75,
    p90 AS percentile_90,
    (SELECT avg_los FROM group_metrics WHERE sepsis_flag = 1) AS avg_los,
    (SELECT mortality FROM group_metrics WHERE sepsis_flag = 1) AS mortality
FROM sepsis_pcts
UNION ALL
SELECT 
    'non_sepsis' AS group_type,
    NULL AS percentile_75,
    NULL AS percentile_90,
    (SELECT avg_los FROM group_metrics WHERE sepsis_flag = 0) AS avg_los,
    (SELECT mortality FROM group_metrics WHERE sepsis_flag = 0) AS mortality
FROM (SELECT 1);