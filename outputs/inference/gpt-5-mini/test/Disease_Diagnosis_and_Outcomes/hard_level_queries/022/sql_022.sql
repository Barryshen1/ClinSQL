WITH dx_flags AS (
  -- admission-level flags for AKI, ARDS, and 5 comorbidities
  SELECT
    d.hadm_id,
    d.subject_id,
    MAX(
      CASE
        WHEN REGEXP_CONTAINS(LOWER(di.long_title), r'acute (kidney|renal)') 
             OR LOWER(di.long_title) LIKE '%acute renal failure%' 
             OR LOWER(di.long_title) LIKE '%acute kidney injury%'
             OR d.icd_code LIKE '584%'    -- ICD-9 acute renal failure patterns
             OR d.icd_code LIKE 'N17%'    -- ICD-10 acute kidney injury
        THEN 1 ELSE 0 END
    ) AS has_aki,
    MAX(
      CASE
        WHEN REGEXP_CONTAINS(LOWER(di.long_title), r'acute (respiratory|respiratory distress)|ards')
             OR d.icd_code LIKE '518.82%'  -- ICD-9 ARDS
             OR d.icd_code LIKE 'J80%'     -- ICD-10 ARDS
        THEN 1 ELSE 0 END
    ) AS has_ards,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(di.long_title), r'hypertension') THEN 1 ELSE 0 END) AS has_htn,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(di.long_title), r'diabetes') THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(
      CASE WHEN REGEXP_CONTAINS(LOWER(di.long_title), r'(chronic (kidney|renal))|(chronic kidney disease)|(ckd)') 
           THEN 1 ELSE 0 END
    ) AS has_ckd,
    MAX(
      CASE WHEN REGEXP_CONTAINS(LOWER(di.long_title), r'(congestive heart failure)|(\bheart failure\b)') THEN 1 ELSE 0 END
    ) AS has_chf,
    MAX(
      CASE WHEN REGEXP_CONTAINS(LOWER(di.long_title), r'(chronic obstructive)|(copd)|(chronic pulmonary)') THEN 1 ELSE 0 END
    ) AS has_copd
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
      ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  GROUP BY d.hadm_id, d.subject_id
),

cohort AS (
  -- join admissions + patient info + diagnosis flags; restrict to female age 40-50 and admissions with AKI
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    dx.has_aki,
    dx.has_ards,
    dx.has_htn,
    dx.has_diabetes,
    dx.has_ckd,
    dx.has_chf,
    dx.has_copd,
    -- comorbidity count among the five selected
    (COALESCE(dx.has_htn,0) + COALESCE(dx.has_diabetes,0) + COALESCE(dx.has_ckd,0) + COALESCE(dx.has_chf,0) + COALESCE(dx.has_copd,0)) AS comorb_count,
    -- composite risk score
    (5 * (COALESCE(dx.has_htn,0) + COALESCE(dx.has_diabetes,0) + COALESCE(dx.has_ckd,0) + COALESCE(dx.has_chf,0) + COALESCE(dx.has_copd,0))
      + CASE WHEN COALESCE(dx.has_ards,0) = 1 THEN 50 ELSE 0 END
    ) AS composite_score,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN dx_flags dx
      ON a.hadm_id = dx.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND dx.has_aki = 1
),

scored AS (
  -- assign quintiles across the cohort ordered by composite score (ties broken by hadm_id)
  SELECT
    *,
    NTILE(5) OVER (ORDER BY composite_score ASC, hadm_id ASC) AS quintile,
    -- LOS in days (integer days between admit and discharge)
    SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) AS los_days,
    -- post-discharge 30-day death flag: only count deaths that occurred after discharge (exclude in-hospital deaths)
    CASE
      WHEN hospital_expire_flag = 0
         AND dod IS NOT NULL
         AND DATE_DIFF(DATE(dod), DATE(dischtime), DAY) BETWEEN 0 AND 30
      THEN 1 ELSE 0 END AS died_within_30_post_discharge
  FROM cohort
)

SELECT
  quintile,
  COUNT(*) AS n_admissions,
  -- 30-day post-discharge mortality percent among all admissions in the quintile
  ROUND(100.0 * SUM(died_within_30_post_discharge) / NULLIF(COUNT(*),0), 2) AS pct_30d_post_discharge_mortality,
  -- ARDS co-occurrence percent
  ROUND(100.0 * SUM(CASE WHEN has_ards = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0), 2) AS pct_ards_cooccurrence,
  -- median LOS (days) among survivors (hospital_expire_flag = 0); uses APPROX_QUANTILES for median
  APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_survivor_los_days
FROM scored
GROUP BY quintile
ORDER BY quintile;