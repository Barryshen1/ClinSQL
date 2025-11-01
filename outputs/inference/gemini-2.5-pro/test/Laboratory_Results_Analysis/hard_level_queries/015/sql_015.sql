WITH
  -- Step 1: Identify ICD codes for ischemic stroke
  ICD_Stroke AS (
    SELECT DISTINCT icd_code, icd_version
    FROM
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
      LOWER(long_title) LIKE '%cerebral infarction%' OR LOWER(long_title) LIKE '%ischemic stroke%'
  ),
  -- Step 2: Create a base cohort of all male inpatients aged 49-59
  -- and flag them as 'stroke' or 'control'
  All_Male_Admissions_Aged_49_59 AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      -- Check if this admission is for an ischemic stroke
      CASE
        WHEN dx.hadm_id IS NOT NULL THEN 1
        ELSE 0
      END AS is_stroke
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    LEFT JOIN (
      -- Subquery to find all hospital admissions with a stroke diagnosis
      SELECT DISTINCT
        diag.hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
      -- FIX: Use a JOIN on two columns instead of a multi-column IN clause
      JOIN
        ICD_Stroke
        ON diag.icd_code = ICD_Stroke.icd_code AND diag.icd_version = ICD_Stroke.icd_version
    ) AS dx
      ON a.hadm_id = dx.hadm_id
    WHERE
      p.gender = 'M'
      AND (
        (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age
      ) BETWEEN 49 AND 59
  ),
  -- Step 3: Calculate the 72-hour lab instability score for every patient in the base cohort
  Cohort_Scores AS (
    SELECT
      c.hadm_id,
      c.admittime,
      c.dischtime,
      c.hospital_expire_flag,
      c.is_stroke,
      -- Count abnormal labs in the first 72 hours of admission
      COUNT(l.labevent_id) AS lab_instability_score
    FROM
      All_Male_Admissions_Aged_49_59 AS c
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.labevents` AS l
      ON c.hadm_id = l.hadm_id
      AND l.flag = 'abnormal'
      -- FIX: Use TIMESTAMP_ADD for TIMESTAMP columns to ensure correct filtering
      AND l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    GROUP BY
      c.hadm_id,
      c.admittime,
      c.dischtime,
      c.hospital_expire_flag,
      c.is_stroke
  ),
  -- Step 4: Calculate the 75th percentile of the score for the stroke cohort
  P75_Score AS (
    SELECT
      APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(75)] AS score_p75
    FROM
      Cohort_Scores
    WHERE
      is_stroke = 1
  ),
  -- Step 5: Analyze the high-instability stroke group (score >= 75th percentile)
  High_Instability_Stroke_Group_Stats AS (
    SELECT
      'high_instability_stroke_group' AS group_name,
      -- FIX: Use TIMESTAMP_DIFF for TIMESTAMP columns to ensure correct LOS calculation
      AVG(TIMESTAMP_DIFF(cs.dischtime, cs.admittime, HOUR) / 24.0) AS avg_los_days,
      AVG(CAST(cs.hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct,
      SUM(cs.lab_instability_score) / COUNT(cs.hadm_id) AS critical_lab_rate
    FROM
      Cohort_Scores AS cs
    WHERE
      cs.is_stroke = 1
      AND cs.lab_instability_score >= (
        SELECT score_p75 FROM P75_Score
      )
  ),
  -- Step 6: Analyze the control group
  Control_Group_Stats AS (
    SELECT
      'age_matched_controls' AS group_name,
      SUM(lab_instability_score) / COUNT(hadm_id) AS critical_lab_rate
    FROM
      Cohort_Scores
    WHERE
      is_stroke = 0
  )
-- Step 7: Union all results into a final summary table
SELECT
  '75th_percentile_lab_instability_score' AS metric,
  CAST(score_p75 AS FLOAT64) AS value
FROM
  P75_Score
UNION ALL
SELECT
  'high_instability_avg_los_days' AS metric,
  avg_los_days
FROM
  High_Instability_Stroke_Group_Stats
UNION ALL
SELECT
  'high_instability_mortality_pct' AS metric,
  mortality_pct
FROM
  High_Instability_Stroke_Group_Stats
UNION ALL
SELECT
  'high_instability_critical_lab_rate' AS metric,
  critical_lab_rate
FROM
  High_Instability_Stroke_Group_Stats
UNION ALL
SELECT
  'control_critical_lab_rate' AS metric,
  critical_lab_rate
FROM
  Control_Group_Stats;