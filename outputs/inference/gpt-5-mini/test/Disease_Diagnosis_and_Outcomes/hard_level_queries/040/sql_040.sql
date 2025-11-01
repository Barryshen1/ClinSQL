WITH ich_admissions AS (
  -- Admissions with any ICH diagnosis (ICD-9: 430/431/432*, ICD-10: I60/I61/I62*)
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (
           icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%'
        ))
     OR (icd_version = 10 AND (
           icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'
        ))
),

diag_counts AS (
  -- Composite risk score proxy: number of distinct diagnosis codes on the admission
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS composite_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

cohort AS (
  -- Admissions for female patients age 69-79 with ICH
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime            AS adm_deathtime,
    p.dod                  AS patient_dod,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    -- best available death timestamp (in-hospital or patient-level date of death)
    COALESCE(CAST(a.deathtime AS TIMESTAMP), CAST(p.dod AS TIMESTAMP)) AS death_time,
    IFNULL(dc.composite_score, 0) AS composite_score,
    -- major complication proxy: any ICU stay during this admission
    CASE WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
        WHERE ic.hadm_id = a.hadm_id
      ) THEN 1 ELSE 0 END AS had_icu
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN ich_admissions ia
    ON a.hadm_id = ia.hadm_id
  LEFT JOIN diag_counts dc
    ON a.hadm_id = dc.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND a.admittime IS NOT NULL
)

-- Final aggregation by quintile of composite score
SELECT
  quintile,
  COUNT(*) AS n,
  -- 30-day mortality percentage
  ROUND(100.0 * SUM(CASE WHEN death_time IS NOT NULL
                          AND death_time <= TIMESTAMP_ADD(CAST(admittime AS TIMESTAMP), INTERVAL 30 DAY)
                     THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_30day_mortality,
  -- Major complication percentage (ICU during admission)
  ROUND(100.0 * SUM(had_icu) / COUNT(*), 2) AS pct_major_complication,
  -- Median LOS (days) among survivors to discharge (hospital_expire_flag = 0)
  ROUND(
    COALESCE(
      (APPROX_QUANTILES(
        CASE
          WHEN hospital_expire_flag = 0 AND dischtime IS NOT NULL
          THEN TIMESTAMP_DIFF(CAST(dischtime AS TIMESTAMP), CAST(admittime AS TIMESTAMP), SECOND) / 86400.0
          ELSE NULL
        END, 100
      ))[OFFSET(50)],
      NULL
    )
  , 2) AS median_survivor_los_days
FROM (
  SELECT c.*,
         NTILE(5) OVER (ORDER BY composite_score) AS quintile
  FROM cohort c
) q
GROUP BY quintile
ORDER BY quintile;