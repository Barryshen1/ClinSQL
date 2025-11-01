WITH patient_stays AS (
    SELECT 
        ie.subject_id, 
        ie.hadm_id, 
        ie.stay_id, 
        ie.intime, 
        ie.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 48 AND 58
),

hr_data AS (
    SELECT 
        ps.stay_id,
        AVG(ce.valuenum) AS avg_hr
    FROM patient_stays ps
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ps.stay_id = ce.stay_id
    WHERE ce.itemid = 220045  -- Heart Rate
        AND ce.valuenum IS NOT NULL
        AND ce.charttime >= ps.intime
        AND ce.charttime < DATETIME_ADD(ps.intime, INTERVAL 48 HOUR)
    GROUP BY ps.stay_id
),

hr_categories AS (
    SELECT 
        stay_id,
        avg_hr,
        CASE 
            WHEN avg_hr < 60 THEN '<60'
            WHEN avg_hr BETWEEN 60 AND 99 THEN '60-99'
            WHEN avg_hr BETWEEN 100 AND 119 THEN '100-119'
            WHEN avg_hr >= 120 THEN '>=120'
            ELSE 'Other'
        END AS hr_category
    FROM hr_data
),

creatinine_baseline AS (
    SELECT 
        ps.stay_id,
        MIN(le.charttime) AS first_charttime,
        FIRST_VALUE(le.valuenum) OVER (PARTITION BY ps.stay_id ORDER BY le.charttime) AS baseline_creat
    FROM patient_stays ps
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ps.hadm_id = le.hadm_id
    WHERE le.itemid = 50912  -- Creatinine
        AND le.valuenum IS NOT NULL
        AND le.charttime >= ps.intime
        AND le.charttime < DATETIME_ADD(ps.intime, INTERVAL 48 HOUR)
    GROUP BY ps.stay_id, le.valuenum, le.charttime
),

creatinine_followup AS (
    SELECT 
        ps.stay_id,
        MAX(le.valuenum) AS max_creat
    FROM patient_stays ps
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ps.hadm_id = le.hadm_id
    WHERE le.itemid = 50912
        AND le.valuenum IS NOT NULL
        AND le.charttime >= ps.intime
        AND le.charttime < DATETIME_ADD(ps.intime, INTERVAL 48 HOUR)
    GROUP BY ps.stay_id
),

aki_stays AS (
    SELECT 
        bl.stay_id,
        CASE 
            WHEN (fu.max_creat >= bl.baseline_creat + 0.3) 
                OR (fu.max_creat >= bl.baseline_creat * 1.5) 
            THEN 1 
            ELSE 0 
        END AS aki
    FROM creatinine_baseline bl
    INNER JOIN creatinine_followup fu
        ON bl.stay_id = fu.stay_id
    WHERE bl.baseline_creat IS NOT NULL
        AND fu.max_creat IS NOT NULL
),

combined_data AS (
    SELECT 
        hc.stay_id,
        hc.hr_category,
        COALESCE(aki.aki, 0) AS aki
    FROM hr_categories hc
    LEFT JOIN aki_stays aki
        ON hc.stay_id = aki.stay_id
)

SELECT 
    hr_category,
    COUNT(*) AS num_stays,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM combined_data), 2) AS percent_stays,
    SUM(aki) AS num_aki,
    ROUND(SUM(aki) * 100.0 / COUNT(*), 2) AS aki_rate_percent
FROM combined_data
GROUP BY hr_category
ORDER BY hr_category;