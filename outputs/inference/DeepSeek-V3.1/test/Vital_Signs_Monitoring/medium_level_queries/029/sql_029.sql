WITH patient_spo2 AS (
    SELECT 
        ie.stay_id,
        AVG(ce.valuenum) AS mean_spo2
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON ie.stay_id = ce.stay_id
    WHERE 
        p.gender = 'M'
        AND DATE_DIFF(DATE(ie.intime), DATE(p.anchor_year, 1, 1), YEAR) + p.anchor_age BETWEEN 73 AND 83
        AND ce.itemid = 220277  -- SpO2
        AND ce.valuenum IS NOT NULL
        AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
    GROUP BY ie.stay_id
    HAVING COUNT(ce.valuenum) > 0
)
SELECT 
    COUNTIF(mean_spo2 <= 92) / COUNT(*) AS percentile_rank
FROM patient_spo2;