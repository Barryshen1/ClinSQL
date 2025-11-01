WITH
  -- Step 1: Identify the base demographic of female patients aged 53-63 at admission
  base_patients AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      -- Calculate age at admission for precision
      (
        p.anchor_age + DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR)
      ) AS age_at_admission
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'F'
  ),
  filtered_patients AS (
    SELECT
      *
    FROM
      base_patients
    WHERE
      age_at_admission BETWEEN 53 AND 63
  ),

  -- Step 2: Identify hospital admissions with an ACS diagnosis
  acs_hadm AS (
    SELECT DISTINCT
      dx.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
      ON dx.icd_code = d_dx.icd_code
      AND dx.icd_version = d_dx.icd_version
    WHERE
      -- Searching text descriptions is more robust than maintaining ICD code lists
      LOWER(d_dx.long_title) LIKE '%myocardial infarction%'
      OR LOWER(d_dx.long_title) LIKE '%unstable angina%'
  ),

  -- Step 3: Create the final ACS and Control cohorts
  cohorts AS (
    SELECT
      fp.subject_id,
      fp.hadm_id,
      fp.admittime,
      fp.dischtime,
      fp.hospital_expire_flag,
      CASE
        WHEN acs.hadm_id IS NOT NULL
        THEN 'ACS'
        ELSE 'Control'
      END AS cohort_type
    FROM filtered_patients AS fp
    LEFT JOIN acs_hadm AS acs
      ON fp.hadm_id = acs.hadm_id
  ),

  -- Step 4: Calculate the lab instability score for each admission
  -- The score is the count of unique lab categories with at least one abnormal result in the first 72h
  instability_scores AS (
    SELECT
      c.hadm_id,
      COUNT(DISTINCT dli.category) AS lab_instability_score
    FROM cohorts AS c
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON c.hadm_id = le.hadm_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
      ON le.itemid = dli.itemid
    WHERE
      le.flag = 'abnormal'
      AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    GROUP BY
      c.hadm_id
  ),

  -- Step 5: Combine cohort data with instability scores and calculate LOS
  final_data AS (
    SELECT
      c.hadm_id,
      c.cohort_type,
      c.hospital_expire_flag,
      COALESCE(s.lab_instability_score, 0) AS lab_instability_score,
      DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days
    FROM cohorts AS c
    LEFT JOIN instability_scores AS s
      ON c.hadm_id = s.hadm_id
  ),

  -- Step 6: For the ACS cohort, divide patients into quartiles based on their score
  acs_quartiles AS (
    SELECT
      *,
      NTILE(4) OVER (
        ORDER BY
          lab_instability_score
      ) AS score_quartile
    FROM final_data
    WHERE
      cohort_type = 'ACS'
  )

-- Final Step: Generate the two requested analyses and union them into a single report
-- Analysis 1: Mortality and LOS per instability score quartile for the ACS cohort
SELECT
  'ACS Quartile Analysis' AS analysis_type,
  CAST(score_quartile AS STRING) AS group_name,
  MIN(lab_instability_score) AS min_score_in_group,
  MAX(lab_instability_score) AS max_score_in_group,
  COUNT(hadm_id) AS num_patients,
  AVG(los_days) AS avg_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate_pct,
  NULL AS avg_lab_instability_score -- Column for alignment in UNION
FROM acs_quartiles
GROUP BY
  score_quartile

UNION ALL

-- Analysis 2: Comparison of the average instability score between ACS and Control cohorts
SELECT
  'ACS vs Control Comparison' AS analysis_type,
  cohort_type AS group_name,
  NULL AS min_score_in_group,
  NULL AS max_score_in_group,
  COUNT(hadm_id) AS num_patients,
  NULL AS avg_los_days,
  NULL AS mortality_rate_pct,
  AVG(lab_instability_score) AS avg_lab_instability_score
FROM final_data
GROUP BY
  cohort_type
ORDER BY
  analysis_type DESC,
  group_name;