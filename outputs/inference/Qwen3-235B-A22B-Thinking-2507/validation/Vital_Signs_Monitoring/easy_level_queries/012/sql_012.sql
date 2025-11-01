WITH eligible_patients AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 49 AND 59
),
icu_stays AS (
    SELECT 
        i.subject_id, 
        i.hadm_id, 
        i.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN eligible_patients e
        ON i.subject_id = e.subject_id AND i.hadm_id = e.hadm_id
),
diastolic_bp AS (
    SELECT 
        c.stay_id,
        c.valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    INNER JOIN icu_stays s
        ON c.stay_id = s.stay_id
    WHERE c.itemid IN (220051, 220180, 225310, 225312)
        AND c.valuenum IS NOT NULL
),
stay_bp AS (
    SELECT 
        stay_id,
        AVG(valuenum) AS mean_bp
    FROM diastolic_bp
    GROUP BY stay_id
)
SELECT 
    APPROX_QUANTILES(mean_bp, 1000)[OFFSET(750)] - APPROX_QUANTILES(mean_bp, 1000)[OFFSET(250)] AS iqr
FROM stay_bp;