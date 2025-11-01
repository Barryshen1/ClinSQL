WITH vital_signs AS (
  SELECT itemid, LOWER(label) AS label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN (
    'heart rate', 'systolic blood pressure', 'diastolic blood pressure',
    'mean blood pressure', 'respiratory rate', 'temperature', 'spo2'
  )
),

-- Step 2: Identify admissions with acute respiratory failure
acute_rf_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (
    (d.icd_version = 9 AND LEFT(d.icd_code,5) IN ('51881', '51882')) OR
    (d.icd_version = 10 AND LEFT(d.icd_code,3) = 'J96')
  )
),

-- Step 3: Build cohort of male ICU patients aged 85-95 with acute respiratory failure
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  INNER JOIN acute_rf_admissions ar
    ON icu.subject_id = ar.subject_id AND icu.hadm_id = ar.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
    -- Only first ICU stay per admission
    AND icu.stay_id = (
      SELECT MIN(stay_id)
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu2
      WHERE icu2.hadm_id = icu.hadm_id
    )
),

-- Step 4: Calculate instability score for each ICU stay in cohort
vital_sign_abnormal AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum,
    vs.label,
    -- Define abnormal ranges for each vital sign
    CASE
      WHEN vs.label = 'heart rate' AND (ce.valuenum < 50 OR ce.valuenum > 120) THEN 1
      WHEN vs.label = 'systolic blood pressure' AND (ce.valuenum < 90 OR ce.valuenum > 180) THEN 1
      WHEN vs.label = 'diastolic blood pressure' AND (ce.valuenum < 40 OR ce.valuenum > 100) THEN 1
      WHEN vs.label = 'mean blood pressure' AND (ce.valuenum < 60 OR ce.valuenum > 120) THEN 1
      WHEN vs.label = 'respiratory rate' AND (ce.valuenum < 10 OR ce.valuenum > 30) THEN 1
      WHEN vs.label = 'temperature' AND (ce.valuenum < 35 OR ce.valuenum > 38.5) THEN 1
      WHEN vs.label = 'spo2' AND (ce.valuenum < 90) THEN 1
      ELSE 0
    END AS is_abnormal
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id AND c.stay_id = ce.stay_id
  INNER JOIN vital_signs vs
    ON ce.itemid = vs.itemid
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),

instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    COUNTIF(is_abnormal = 1) AS instability_score
  FROM vital_sign_abnormal
  GROUP BY subject_id, hadm_id, stay_id
),

-- Step 5: Merge with cohort and admissions for LOS and mortality
cohort_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.los,
    s.instability_score,
    a.hospital_expire_flag
  FROM cohort c
  LEFT JOIN instability_scores s
    ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id AND c.stay_id = s.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.subject_id = a.subject_id AND c.hadm_id = a.hadm_id
  WHERE s.instability_score IS NOT NULL
),

-- Step 6: Calculate percentile rank of score 85
percentile_rank AS (
  SELECT
    COUNTIF(instability_score <= 85) / COUNT(*) * 100 AS percentile_rank_85
  FROM cohort_scores
),

-- Step 7: Find most unstable quartile threshold
quartiles AS (
  SELECT
    APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS quartile_cutoff -- 75th percentile
  FROM cohort_scores
),

-- Step 8: LOS and mortality for most unstable quartile
unstable_quartile AS (
  SELECT
    AVG(los) AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM cohort_scores, quartiles
  WHERE instability_score >= quartiles.quartile_cutoff
)

-- Final output
SELECT
  pr.percentile_rank_85 AS percentile_rank_of_score_85,
  uq.avg_icu_los,
  uq.mortality_rate
FROM percentile_rank pr
CROSS JOIN unstable_quartile uq;