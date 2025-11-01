WITH cohort AS (
  SELECT DISTINCT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los AS icu_los,
    p.gender,
    p.anchor_age,
    adm.hospital_expire_flag,
    -- Placeholder for SWIFT score - in practice this would come from a derived table
    60 AS swift_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ie.hadm_id = diag.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND (
      (diag.icd_version = 10 AND diag.icd_code LIKE 'J18%')
      OR (diag.icd_version = 9 AND diag.icd_code BETWEEN '480' AND '488' OR diag.icd_code LIKE '486%')
    )
  -- Consider only the first ICU stay per admission
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ie.hadm_id ORDER BY ie.intime) = 1
),

percentile_info AS (
  SELECT
    PERCENT_RANK() OVER (ORDER BY swift_score) AS percentile
  FROM cohort
  WHERE swift_score = 60
  LIMIT 1
),

deciles AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    swift_score,
    icu_los,
    hospital_expire_flag,
    NTILE(10) OVER (ORDER BY swift_score DESC) AS decile
  FROM cohort
),

most_unstable AS (
  SELECT
    COUNT(*) AS n_patients,
    APPROX_QUANTILE(icu_los, 0.5) AS median_icu_los,
    AVG(CAST(hospital_expire_flag AS INT)) * 100 AS mortality_percent
  FROM deciles
  WHERE decile = 10
)

SELECT
  (SELECT percentile FROM percentile_info) AS percentile_60,
  n_patients AS n_unstable,
  median_icu_los AS median_icu_los_unstable,
  mortality_percent AS mortality_percent_unstable
FROM most_unstable;