WITH eligible_stays AS (
    SELECT i.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 49 AND 59
      AND (i.first_careunit LIKE '%Step Down%' 
           OR i.first_careunit LIKE '%IMC%' 
           OR i.first_careunit LIKE '%Intermediate Care%')
),

bp_measurements AS (
    SELECT es.stay_id, c.valuenum
    FROM eligible_stays es
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON es.stay_id = c.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
    WHERE (d.label LIKE '%Diastolic%' OR d.label = 'DBP')
      AND c.valuenum IS NOT NULL
      AND c.valuenum BETWEEN 20 AND 120
),

mean_bp_per_stay AS (
    SELECT stay_id, AVG(valuenum) AS mean_diastolic_bp
    FROM bp_measurements
    GROUP BY stay_id
),

percentiles AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY mean_diastolic_bp) AS q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY mean_diastolic_bp) AS q3
    FROM mean_bp_per_stay
)

SELECT q3 - q1 AS iqr
FROM percentiles;