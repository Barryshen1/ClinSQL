WITH eligible_patients AS (
    SELECT 
        subject_id,
        anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
        AND anchor_age BETWEEN 90 AND 100
),
icu_stays AS (
    SELECT 
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN eligible_patients p ON i.subject_id = p.subject_id
),
spo2_data AS (
    SELECT 
        s.subject_id,
        s.hadm_id,
        s.stay_id,
        AVG(c.valuenum) AS avg_spo2_24h
    FROM icu_stays s
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
        ON s.subject_id = c.subject_id 
        AND s.hadm_id = c.hadm_id 
        AND s.stay_id = c.stay_id
    WHERE c.itemid = 220277  -- SpO2 itemid for MIMIC-IV
        AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
        AND c.valuenum IS NOT NULL
    GROUP BY s.subject_id, s.hadm_id, s.stay_id
),
aki_data AS (
    SELECT 
        s.subject_id,
        s.hadm_id,
        s.stay_id,
        MAX(CASE WHEN l.valuenum > 1.5 THEN 1 ELSE 0 END) AS aki_flag
    FROM icu_stays s
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
        ON s.subject_id = l.subject_id 
        AND s.hadm_id = l.hadm_id
    WHERE l.itemid = 50809  -- Creatinine itemid for MIMIC-IV (Blood)
        AND l.charttime BETWEEN s.intime AND s.outtime
        AND l.valuenum IS NOT NULL
    GROUP BY s.subject_id, s.hadm_id, s.stay_id
),
combined_data AS (
    SELECT 
        s.subject_id,
        s.hadm_id,
        s.stay_id,
        spo2.avg_spo2_24h,
        aki.aki_flag,
        CASE 
            WHEN spo2.avg_spo2_24h < 90 THEN '<90'
            WHEN spo2.avg_spo2_24h BETWEEN 90 AND 92 THEN '90-92'
            WHEN spo2.avg_spo2_24h BETWEEN 93 AND 95 THEN '93-95'
            WHEN spo2.avg_spo2_24h > 95 THEN '>95'
            ELSE 'Missing'
        END AS spo2_category
    FROM icu_stays s
    LEFT JOIN spo2_data spo2 
        ON s.subject_id = spo2.subject_id 
        AND s.hadm_id = spo2.hadm_id 
        AND s.stay_id = spo2.stay_id
    LEFT JOIN aki_data aki 
        ON s.subject_id = aki.subject_id 
        AND s.hadm_id = aki.hadm_id 
        AND s.stay_id = aki.stay_id
)
SELECT 
    spo2_category,
    COUNT(*) AS N,
    AVG(avg_spo2_24h) AS mean_spo2,
    APPROX_QUANTILES(avg_spo2_24h, 100)[OFFSET(50)] AS median_spo2,
    APPROX_QUANTILES(avg_spo2_24h, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(avg_spo2_24h, 100)[OFFSET(75)] AS q3,
    (APPROX_QUANTILES(avg_spo2_24h, 100)[OFFSET(75)] - APPROX_QUANTILES(avg_spo2_24h, 100)[OFFSET(25)]) AS IQR,
    AVG(aki_flag) AS AKI_rate
FROM combined_data
WHERE spo2_category IS NOT NULL
GROUP BY spo2_category
ORDER BY 
    CASE spo2_category
        WHEN '<90' THEN 1
        WHEN '90-92' THEN 2
        WHEN '93-95' THEN 3
        WHEN '>95' THEN 4
    END;