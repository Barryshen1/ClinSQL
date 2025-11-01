WITH
-- Get male patients aged 85-95
eligible_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM CURRENT_DATE()) - p.anchor_year + p.anchor_age AS current_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM CURRENT_DATE()) - p.anchor_year + p.anchor_age) BETWEEN 85 AND 95
),

-- Get patients with acute respiratory failure
arf_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND (
      -- ICD-10 codes for acute respiratory failure
      (d.icd_version = 10 AND d.icd_code LIKE 'J96.0%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'J96.2%')
      -- Add other relevant codes if needed
    )
),

-- Get first ICU stay for each admission
first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY i.intime) AS icu_stay_rank
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  WHERE
    i.hadm_id IN (SELECT hadm_id FROM arf_patients)
  QUALIFY icu_stay_rank = 1
),

-- Calculate vital sign instability score for first 24 hours
vital_sign_scores AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    -- Calculate a composite instability score (example calculation - adjust as needed)
    -- This is a simplified example - actual calculation would be more complex
    SUM(
      CASE
        WHEN di.category = 'Heart Rate' AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1
        WHEN di.category = 'Blood Pressure' AND (ce.valuenum < 90 OR ce.valuenum > 140) THEN 1
        WHEN di.category = 'Respiratory Rate' AND (ce.valuenum < 12 OR ce.valuenum > 20) THEN 1
        WHEN di.category = 'Oxygen Saturation' AND ce.valuenum < 90 THEN 1
        ELSE 0
      END
    ) AS instability_score
  FROM
    first_icu_stays f
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    f.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    ce.charttime BETWEEN f.intime AND DATETIME_ADD(f.intime, INTERVAL 24 HOUR)
    AND di.category IN ('Heart Rate', 'Blood Pressure', 'Respiratory Rate', 'Oxygen Saturation')
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id
),

-- Calculate percentile rank for score of 85
percentile_rank AS (
  SELECT
    COALESCE(
      (SELECT PERCENT_RANK() OVER (ORDER BY instability_score)
       FROM vital_sign_scores
       WHERE instability_score = 85
       LIMIT 1),
      NULL
    ) AS percentile
),

-- Assign quartiles
quartile_assignment AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    instability_score,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile
  FROM
    vital_sign_scores
),

-- Get stats for most unstable quartile
quartile_stats AS (
  SELECT
    AVG(i.los) AS avg_icu_los,
    AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate
  FROM
    quartile_assignment qa
  JOIN
    first_icu_stays i ON qa.stay_id = i.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  WHERE
    qa.quartile = 1  -- Most unstable quartile
)

-- Final results
SELECT
  (SELECT percentile FROM percentile_rank) AS percentile_rank_for_score_85,
  (SELECT avg_icu_los FROM quartile_stats) AS avg_icu_los_most_unstable_quartile,
  (SELECT mortality_rate FROM quartile_stats) AS mortality_rate_most_unstable_quartile;