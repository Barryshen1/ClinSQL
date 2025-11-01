WITH heart_failure_adm AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        p.gender,
        p.anchor_age,
        a.hospital_expire_flag,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 83 AND 93
      AND (
        (d.icd_version = 9 AND d.icd_code LIKE '428%')   -- ICD-9 HF
        OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%') -- ICD-10 HF
      )
    GROUP BY a.subject_id, a.hadm_id, p.gender, p.anchor_age, a.hospital_expire_flag, a.admittime, a.dischtime
),
icu_flags AS (
    SELECT DISTINCT
        hadm_id,
        1 AS icu_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
comorbidities AS (
    SELECT
        d.subject_id,
        d.hadm_id,
        MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '585%')
                  OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%')
                 THEN 1 ELSE 0 END) AS ckd,
        MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%')
                  OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' 
                                               OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%'))
                 THEN 1 ELSE 0 END) AS diabetes,
        MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '401%' OR d.icd_code LIKE '402%' OR d.icd_code LIKE '403%' OR d.icd_code LIKE '404%' OR d.icd_code LIKE '405%'))
                  OR (d.icd_version = 10 AND d.icd_code LIKE 'I1%')
                 THEN 1 ELSE 0 END) AS hypertension,
        MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '491%' OR d.icd_code LIKE '492%' OR d.icd_code LIKE '496%'))
                  OR (d.icd_version = 10 AND d.icd_code LIKE 'J44%')
                 THEN 1 ELSE 0 END) AS copd,
        MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '140' AND '239')
                  OR (d.icd_version = 10 AND (
                       d.icd_code LIKE 'C%' OR d.icd_code LIKE 'D0%' OR d.icd_code LIKE 'D1%' OR d.icd_code LIKE 'D2%' OR d.icd_code LIKE 'D3%' OR d.icd_code LIKE 'D4%'
                  ))
                 THEN 1 ELSE 0 END) AS cancer
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    GROUP BY d.subject_id, d.hadm_id
),
cohort AS (
    SELECT
        hfa.subject_id,
        hfa.hadm_id,
        COALESCE(ic.icu_flag, 0) AS icu_flag,
        hfa.los_days,
        CASE WHEN hfa.los_days < 8 THEN '<8' ELSE '≥8' END AS los_group,
        c.ckd,
        c.diabetes,
        -- Count comorbidities excluding HF
        (COALESCE(c.ckd,0) + COALESCE(c.diabetes,0) + COALESCE(c.hypertension,0) + COALESCE(c.copd,0) + COALESCE(c.cancer,0)) AS comorb_count,
        hfa.hospital_expire_flag
    FROM heart_failure_adm hfa
    LEFT JOIN icu_flags ic
      ON hfa.hadm_id = ic.hadm_id
    LEFT JOIN comorbidities c
      ON hfa.subject_id = c.subject_id AND hfa.hadm_id = c.hadm_id
),
cohort_with_burden AS (
    SELECT
        *,
        CASE 
          WHEN comorb_count <= 1 THEN '0-1'
          WHEN comorb_count = 2 THEN '2'
          WHEN comorb_count >= 3 THEN '≥3'
        END AS comorb_group
    FROM cohort
)
SELECT
    icu_flag,
    los_group,
    comorb_group,
    COUNT(*) AS n_admissions,
    ROUND(100*AVG(hospital_expire_flag),1) AS mortality_pct,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
    ROUND(100*AVG(CAST(ckd AS FLOAT64)),1) AS ckd_pct,
    ROUND(100*AVG(CAST(diabetes AS FLOAT64)),1) AS diabetes_pct
FROM cohort_with_burden
GROUP BY icu_flag, los_group, comorb_group
ORDER BY icu_flag, los_group, comorb_group;