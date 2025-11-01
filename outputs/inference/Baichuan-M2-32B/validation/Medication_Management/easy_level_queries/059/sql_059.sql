WITH patient_birth AS (
    SELECT 
        subject_id,
        DATE_SUB(CAST(CONCAT(anchor_year, '-01-01') AS DATE), INTERVAL anchor_age YEAR) AS birth_date
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE anchor_year IS NOT NULL 
      AND anchor_age IS NOT NULL
),
admissions_with_age AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.gender,
        TIMESTAMP_DIFF(a.admittime, p.birth_date, YEAR) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN patient_birth p ON a.subject_id = p.subject_id
    WHERE a.admittime IS NOT NULL
      AND a.dischtime IS NOT NULL
),
eligible_admissions AS (
    SELECT 
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        gender,
        age_at_admission
    FROM admissions_with_age
    WHERE gender = 'M'
      AND age_at_admission BETWEEN 38 AND 48
),
arbs AS (
    SELECT 
        subject_id,
        hadm_id,
        starttime,
        stoptime,
        drug
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE drug IS NOT NULL
      AND starttime IS NOT NULL
      AND REGEXP_CONTAINS(drug, r'(?i)\b(losartan|valsartan|candesartan|irbesartan|telmisartan|olmesartan|eprosartan|azilsartan)\b')
),
prescriptions_with_duration AS (
    SELECT 
        e.subject_id,
        e.hadm_id,
        p.starttime,
        COALESCE(p.stoptime, e.dischtime) AS end_time,
        DATEDIFF(COALESCE(p.stoptime, e.dischtime), p.starttime) AS duration_days
    FROM eligible_admissions e
    INNER JOIN arbs p 
        ON e.subject_id = p.subject_id 
        AND e.hadm_id = p.hadm_id
    WHERE p.starttime BETWEEN e.admittime AND e.dischtime
      AND DATEDIFF(COALESCE(p.stoptime, e.dischtime), p.starttime) > 0
)
SELECT 
    PERCENTILE_CONT(duration_days, 0.75) WITHIN GROUP (ORDER BY duration_days) AS p75
FROM prescriptions_with_duration;