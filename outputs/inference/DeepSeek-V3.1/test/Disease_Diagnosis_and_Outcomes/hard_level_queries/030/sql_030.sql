WITH cohort AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        p.anchor_age,
        a.admittime,
        a.dischtime,
        a.deathtime,
        a.hospital_expire_flag,
        COUNT(DISTINCT diag.icd_code) AS diagnosis_count,
        CASE WHEN a.hospital_expire_flag = 1 OR i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS major_complication,
        COUNT(DISTINCT diag.icd_code) + 20 * (CASE WHEN a.hospital_expire_flag = 1 OR i.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS composite_score,
        CASE WHEN a.deathtime IS NOT NULL AND DATETIME_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1 ELSE 0 END AS mortality_30d,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON a.hadm_id = diag.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.hadm_id = i.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 64 AND 74
        AND a.hadm_id IN (
            SELECT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
                ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
            WHERE d.long_title LIKE '%gastrointestinal hemorrhage%'
                OR d.long_title LIKE '%haemorrhage%'
                OR d.icd_code LIKE 'K25.0%' OR d.icd_code LIKE 'K25.2%' OR d.icd_code LIKE 'K25.4%' OR d.icd_code LIKE 'K25.6%'
                OR d.icd_code LIKE 'K26.0%' OR d.icd_code LIKE 'K26.2%' OR d.icd_code LIKE 'K26.4%' OR d.icd_code LIKE 'K26.6%'
                OR d.icd_code LIKE 'K92.2%'
                OR d.icd_code LIKE 'I85.01%' OR d.icd_code LIKE 'I85.11%'
        )
    GROUP BY p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag, i.stay_id
),
quintiles AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY composite_score) AS quintile
    FROM cohort
)
SELECT 
    quintile,
    COUNT(*) AS n,
    AVG(composite_score) AS mean_score,
    AVG(mortality_30d) * 100 AS mortality_30d_pct,
    AVG(major_complication) * 100 AS major_complication_pct,
    APPROX_QUANTILES(
        CASE WHEN mortality_30d = 0 THEN los_days ELSE NULL END, 
        100
    )[OFFSET(50)] AS median_los_survivors_days
FROM quintiles
GROUP BY quintile
ORDER BY quintile;