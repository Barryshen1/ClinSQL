WITH cohort AS (
  SELECT 
    icustays.stay_id,
    icustays.hadm_id,
    icustays.los,
    admissions.hospital_expire_flag,
    patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year) AS age,
    -- Compute instability score as count of abnormal vital signs in first 24h
    (SELECT COUNT(*)
     FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
     INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
       ON ce.itemid = d.itemid
     WHERE ce.stay_id = icustays.stay_id
       AND ce.charttime <= icustays.intime + INTERVAL '1' DAY
       -- Filter for vital signs (common item categories)
       AND d.category IN ('Vital Signs', ' cardiovascular')
       -- Flag abnormalities using normal ranges
       AND (
         (d.lownormalvalue IS NOT NULL AND ce.valuenum < d.lownormalvalue) 
         OR (d.highnormalvalue IS NOT NULL AND ce.valuenum > d.highnormalvalue)
       )
    ) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` admissions
    ON icustays.hadm_id = admissions.hadm_id
  WHERE 
    patients.gender = 'M'
    AND (patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year)) BETWEEN 78 AND 88
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
        ON diag.icd_code = d_diag.icd_code 
        AND diag.icd_version = d_diag.icd_version
      WHERE diag.hadm_id = admissions.hadm_id
        AND diag.icd_version = 10
        -- Fix: ICD codes stored without decimals (e.g., A400 not A40.0)
        AND (d_diag.icd_code LIKE 'A40%' OR d_diag.icd_code LIKE 'A41%')
    )
),
cohort_with_quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM cohort
  -- Exclude stays with no instability score (no vitals recorded)
  WHERE instability_score IS NOT NULL
),
percentile_calc AS (
  SELECT
    (COUNTIF(instability_score <= 85) * 100.0) / COUNT(*) AS percentile_rank
  FROM cohort
  WHERE instability_score IS NOT NULL
),
quartile4_stats AS (
  SELECT
    AVG(los) AS mean_icu_los,
    AVG(hospital_expire_flag) AS hospital_mortality
  FROM cohort_with_quartiles
  WHERE quartile = 4
)
SELECT
  (SELECT percentile_rank FROM percentile_calc) AS instability_score_percentile_rank,
  (SELECT mean_icu_los FROM quartile4_stats) AS quartile4_mean_icu_los,
  (SELECT hospital_mortality FROM quartile4_stats) AS quartile4_hospital_mortality;