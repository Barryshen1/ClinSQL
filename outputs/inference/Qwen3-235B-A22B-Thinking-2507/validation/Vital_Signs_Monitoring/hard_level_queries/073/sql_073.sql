WITH patients_cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 47 AND 57
),
ich_diagnoses AS (
  SELECT 
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE 
    (icd_version = 9 AND icd_code IN ('430','431','432'))
    OR 
    (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('I60','I61','I62')))
  GROUP BY hadm_id
),
icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
),
cohort_base AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM patients_cohort p
  INNER JOIN ich_diagnoses d ON p.hadm_id = d.hadm_id
  INNER JOIN icu_stays i ON p.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.hadm_id = a.hadm_id
),
-- Calculate vital sign instability score (proxy: count of abnormal vital signs)
vital_sign_scores AS (
  SELECT 
    c.stay_id,
    COUNT(*) AS score
  FROM cohort_base c
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON c.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    -- Filter for common vital sign itemids
    AND ce.itemid IN (
      220045, -- Heart Rate
      220179, -- Non Invasive Blood Pressure systolic
      220050  -- Arterial Blood Pressure systolic
    )
    -- Count abnormal values as indicators of instability
    AND (
      (ce.itemid = 220045 AND (ce.valuenum < 60 OR ce.valuenum > 100)) OR
      ((ce.itemid = 220179 OR ce.itemid = 220050) AND (ce.valuenum < 90 OR ce.valuenum > 160))
    )
  GROUP BY c.stay_id
),
cohort_with_score AS (
  SELECT 
    c.*,
    COALESCE(v.score, 0) AS score
  FROM cohort_base c
  LEFT JOIN vital_sign_scores v ON c.stay_id = v.stay_id
),
cohort_with_decile AS (
  SELECT *,
    NTILE(10) OVER (ORDER BY score DESC) AS decile
  FROM cohort_with_score
)

SELECT 
  -- Calculate percentile of score 75
  (SELECT COUNT(*) FROM cohort_with_score WHERE score <= 75) * 100.0 / COUNT(*) AS percentile_75,
  -- Average ICU LOS for top decile
  AVG(CASE WHEN decile = 1 THEN los ELSE NULL END) AS avg_los_top_decile,
  -- Mortality rate for top decile
  AVG(CASE WHEN decile = 1 THEN hospital_expire_flag ELSE NULL END) AS mortality_top_decile
FROM cohort_with_decile;