WITH cohort AS (
    SELECT 
        ie.subject_id, 
        ie.hadm_id, 
        ie.stay_id,
        ie.intime,
        ie.outtime,
        p.anchor_age
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 90 AND 100
),
spo2_avg AS (
    SELECT 
        c.stay_id,
        AVG(ce.valuenum) AS avg_spo2
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    WHERE ce.itemid = 220277  -- SpO2
        AND ce.valuenum IS NOT NULL
        AND ce.charttime >= c.intime
        AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    GROUP BY c.stay_id
),
aki_flag AS (
    SELECT 
        c.stay_id,
        CASE WHEN COUNT(d.icd_code) > 0 THEN 1 ELSE 0 END AS aki
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON c.hadm_id = d.hadm_id
    WHERE d.icd_code LIKE 'N17%'
        AND d.icd_version = 10
    GROUP BY c.stay_id
),
binned AS (
    SELECT 
        sa.stay_id,
        sa.avg_spo2,
        CASE 
            WHEN sa.avg_spo2 < 90 THEN '<90'
            WHEN sa.avg_spo2 BETWEEN 90 AND 92 THEN '90-92'
            WHEN sa.avg_spo2 BETWEEN 93 AND 95 THEN '93-95'
            ELSE '>95'
        END AS spo2_bin,
        af.aki
    FROM spo2_avg sa
    INNER JOIN cohort c ON sa.stay_id = c.stay_id
    LEFT JOIN aki_flag af ON sa.stay_id = af.stay_id
)
SELECT 
    spo2_bin,
    COUNT(stay_id) AS N,
    AVG(avg_spo2) AS mean_spo2,
    APPROX_QUANTILES(avg_spo2, 100)[OFFSET(50)] AS median_spo2,
    APPROX_QUANTILES(avg_spo2, 100)[OFFSET(75)] - APPROX_QUANTILES(avg_spo2, 100)[OFFSET(25)] AS iqr_spo2,
    AVG(aki) AS aki_rate
FROM binned
GROUP BY spo2_bin
ORDER BY spo2_bin;