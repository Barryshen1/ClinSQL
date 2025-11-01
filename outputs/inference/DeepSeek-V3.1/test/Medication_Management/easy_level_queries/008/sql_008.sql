WITH cohort AS (
    SELECT 
        p.subject_id, 
        a.hadm_id, 
        a.admittime, 
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 64 AND 74
),

aspirin_prescriptions AS (
    SELECT 
        pr.hadm_id,
        pr.starttime,
        pr.stoptime,
        pr.drug
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    INNER JOIN cohort c
        ON pr.hadm_id = c.hadm_id
    WHERE LOWER(pr.drug) LIKE '%aspirin%' 
        OR LOWER(pr.drug) LIKE '%acetylsalicylic%'
),

p2y12_prescriptions AS (
    SELECT 
        pr.hadm_id,
        pr.starttime,
        pr.stoptime,
        pr.drug
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    INNER JOIN cohort c
        ON pr.hadm_id = c.hadm_id
    WHERE LOWER(pr.drug) LIKE '%clopidogrel%'
        OR LOWER(pr.drug) LIKE '%ticagrelor%'
        OR LOWER(pr.drug) LIKE '%prasugrel%'
),

eligible_admissions AS (
    SELECT DISTINCT a.hadm_id
    FROM aspirin_prescriptions a
    INNER JOIN p2y12_prescriptions p
        ON a.hadm_id = p.hadm_id
),

all_antiplatelets AS (
    SELECT 
        pr.hadm_id,
        pr.starttime,
        COALESCE(pr.stoptime, c.dischtime) AS endtime,
        pr.drug
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    INNER JOIN eligible_admissions e
        ON pr.hadm_id = e.hadm_id
    INNER JOIN cohort c
        ON pr.hadm_id = c.hadm_id
    WHERE (LOWER(pr.drug) LIKE '%aspirin%' 
            OR LOWER(pr.drug) LIKE '%acetylsalicylic%'
            OR LOWER(pr.drug) LIKE '%clopidogrel%'
            OR LOWER(pr.drug) LIKE '%ticagrelor%'
            OR LOWER(pr.drug) LIKE '%prasugrel%')
        AND pr.starttime >= c.admittime
        AND pr.starttime <= c.dischtime
),

durations AS (
    SELECT
        hadm_id,
        drug,
        DATETIME_DIFF(endtime, starttime, HOUR) / 24.0 AS duration_days
    FROM all_antiplatelets
    WHERE endtime > starttime
)

SELECT 
    APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM durations;