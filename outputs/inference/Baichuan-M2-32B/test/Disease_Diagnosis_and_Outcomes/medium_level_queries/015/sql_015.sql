WITH cohort AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.hospital_expire_flag,
        CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_status,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        COALESCE( (SELECT COUNT(DISTINCT d.icd_code) 
                   FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
                   WHERE d.hadm_id = a.hadm_id
                     AND d.icd_code NOT BETWEEN 'I60' AND 'I69'
                     AND d.icd_version = 10), 0) AS comorbidity_count
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.hadm_id = i.hadm_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 48 AND 58
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_stroke
          WHERE d_stroke.hadm_id = a.hadm_id
            AND d_stroke.icd_code BETWEEN 'I60' AND 'I69'
            AND d_stroke.icd_version = 10
      )
),
grouped AS (
    SELECT 
        icu_status,
        CASE 
            WHEN los_days <= 5 THEN '≤5 days'
            ELSE '>5 days'
        END AS los_group,
        CASE 
            WHEN comorbidity_count BETWEEN 0 AND 2 THEN 'Low'
            WHEN comorbidity_count BETWEEN 3 AND 5 THEN 'Medium'
            WHEN comorbidity_count >= 6 THEN 'High'
        END AS comorbidity_group,
        COUNT(*) AS n,
        SUM(hospital_expire_flag) AS deaths
    FROM cohort
    GROUP BY icu_status, los_group, comorbidity_group
)
SELECT 
    icu_status,
    los_group,
    comorbidity_group,
    n,
    deaths,
    deaths / n AS mortality_rate,
    CASE 
        WHEN n = 0 THEN NULL
        ELSE ( (deaths / n) + (1.96*1.96)/(2*n) - 1.96 * SQRT( ( (deaths/n) * (1 - deaths/n) + (1.96*1.96)/(4*n) ) / n ) ) / (1 + (1.96*1.96)/n )
    END AS lower_bound,
    CASE 
        WHEN n = 0 THEN NULL
        ELSE ( (deaths / n) + (1.96*1.96)/(2*n) + 1.96 * SQRT( ( (deaths/n) * (1 - deaths/n) + (1.96*1.96)/(4*n) ) / n ) ) / (1 + (1.96*1.96)/n )
    END AS upper_bound
FROM grouped
ORDER BY icu_status, los_group, comorbidity_group;