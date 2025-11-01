WITH sepsis_patients AS (
    SELECT 
        p.subject_id,
        p.anchor_age,
        p.gender,
        i.stay_id,
        i.intime,
        i.los,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 78 AND 88
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = i.hadm_id
                AND (
                    (d.icd_version = 9 AND (d.icd_code LIKE '038%' OR d.icd_code IN ('99591', '99592')))
                    OR (d.icd_version = 10 AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%'))
                )
        )
),
saps_scores AS (
    SELECT 
        sp.subject_id,
        sp.stay_id,
        sp.intime,
        sp.los,
        sp.hospital_expire_flag,
        ce.valuenum AS saps_score
    FROM sepsis_patients sp
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON sp.stay_id = ce.stay_id
        AND ce.itemid = 223762
        AND ce.charttime BETWEEN sp.intime AND sp.intime + INTERVAL '24' HOUR
    WHERE ce.valuenum IS NOT NULL
),
score_data AS (
    SELECT 
        saps_score,
        los,
        hospital_expire_flag
    FROM saps_scores
),
quartiles AS (
    SELECT 
        saps_score,
        los,
        hospital_expire_flag,
        NTILE(4) OVER (ORDER BY saps_score) AS quartile
    FROM score_data
)
SELECT 
    (COUNT(CASE WHEN saps_score <= 85 THEN 1 END) * 100.0 / COUNT(*)) AS percentile_rank,
    AVG(CASE WHEN quartile = 4 THEN los END) AS mean_los_q4,
    AVG(CASE WHEN quartile = 4 THEN hospital_expire_flag END) AS mortality_q4
FROM quartiles;