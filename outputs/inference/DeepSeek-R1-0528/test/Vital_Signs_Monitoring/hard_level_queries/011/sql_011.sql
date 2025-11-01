WITH pneumonia_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'pneumonia')
),
pneumonia_patients AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN pneumonia_codes pc
    ON diag.icd_code = pc.icd_code
    AND diag.icd_version = pc.icd_version
),
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate exact age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN pneumonia_patients pp
    ON icu.hadm_id = pp.hadm_id
    AND icu.subject_id = pp.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE
    p.gender = 'F'
    -- Filter for patients aged 55-65 at ICU admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 55 AND 65
    -- Exclude stays shorter than 24 hours
    AND DATETIME_DIFF(icu.outtime, icu.intime, HOUR) >= 24
),
cohort_instability AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    los,
    hospital_expire_flag,
    /* USER MUST REPLACE THIS PLACEHOLDER WITH ACTUAL INSTABILITY SCORE LOGIC.
       Example (SOFA in first 24 hours):
       WITH first_day_data AS (...)
       SELECT ...,
         (respiration_score + coagulation_score + ...) AS instability_score
    */
    0 AS instability_score  -- Replace with real calculation
  FROM cohort
),
cohort_instability_valid AS (
  SELECT *
  FROM cohort_instability
  WHERE instability_score IS NOT NULL  -- Ensure valid scores here
),
percentile_calc AS (
  SELECT
    COUNTIF(instability_score <= 60) * 100.0 / COUNT(*) AS percentile_60
  FROM cohort_instability_valid
),
deciles AS (
  SELECT
    *,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM cohort_instability_valid
),
top_decile_summary AS (
  SELECT
    AVG(los) AS avg_icu_los,
    SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_percentage
  FROM deciles
  WHERE decile = 1  -- Most unstable decile
)
SELECT
  (SELECT percentile_60 FROM percentile_calc) AS percentile_for_score_60,
  (SELECT avg_icu_los FROM top_decile_summary) AS avg_icu_los_top_decile,
  (SELECT mortality_percentage FROM top_decile_summary) AS mortality_percentage_top_decile;