WITH cohort AS (
    SELECT 
        p.subject_id, 
        a.hadm_id,
        p.anchor_age,
        a.hospital_expire_flag,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 35 AND 45
        AND d.icd_code LIKE 'K85%'
        AND d.icd_version = 10
),
diagnosis_counts AS (
    SELECT 
        hadm_id,
        COUNT(DISTINCT icd_code) AS num_diagnoses
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
),
major_complications AS (
    SELECT 
        hadm_id,
        MAX(CASE WHEN 
            (icd_code LIKE 'J96%' OR 
             icd_code LIKE 'R57%' OR 
             icd_code LIKE 'N17%' OR
             icd_code = 'K85.2') 
            THEN 1 ELSE 0 END) AS has_major_complication
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10
    GROUP BY hadm_id
),
risk_scores AS (
    SELECT 
        c.*,
        dc.num_diagnoses,
        mc.has_major_complication,
        dc.num_diagnoses + 5 * mc.has_major_complication AS risk_score
    FROM cohort c
    LEFT JOIN diagnosis_counts dc
        ON c.hadm_id = dc.hadm_id
    LEFT JOIN major_complications mc
        ON c.hadm_id = mc.hadm_id
),
quartiles AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile
    FROM risk_scores
)
SELECT 
    risk_quartile,
    COUNT(*) AS n_admissions,
    SUM(hospital_expire_flag) AS in_hospital_deaths,
    ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100, 2) AS mortality_rate_percent,
    ROUND(SUM(has_major_complication) / COUNT(*) * 100, 2) AS major_complication_rate_percent,
    ROUND(MIN(IF(hospital_expire_flag = 0, los_days, NULL)), 2) AS min_survivor_los,
    ROUND(MAX(IF(hospital_expire_flag = 0, los_days, NULL)), 2) AS max_survivor_los,
    ROUND(AVG(IF(hospital_expire_flag = 0, los_days, NULL)), 2) AS mean_survivor_los,
    ROUND(APPROX_QUANTILE(IF(hospital_expire_flag = 0, los_days, NULL), 0.5), 2) AS median_survivor_los
FROM quartiles
GROUP BY risk_quartile
UNION ALL
SELECT 
    NULL AS risk_quartile,
    COUNT(*) AS n_admissions,
    SUM(hospital_expire_flag) AS in_hospital_deaths,
    ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100, 2) AS mortality_rate_percent,
    ROUND(SUM(has_major_complication) / COUNT(*) * 100, 2) AS major_complication_rate_percent,
    ROUND(MIN(IF(hospital_expire_flag = 0, los_days, NULL)), 2) AS min_survivor_los,
    ROUND(MAX(IF(hospital_expire_flag = 0, los_days, NULL)), 2) AS max_survivor_los,
    ROUND(AVG(IF(hospital_expire_flag = 0, los_days, NULL)), 2) AS mean_survivor_los,
    ROUND(APPROX_QUANTILE(IF(hospital_expire_flag = 0, los_days, NULL), 0.5), 2) AS median_survivor_los
FROM quartiles
ORDER BY risk_quartile;