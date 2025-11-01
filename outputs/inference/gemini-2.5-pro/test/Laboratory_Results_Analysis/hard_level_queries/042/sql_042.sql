WITH
  ich_hadms AS (
    -- Step 1: Identify all hospital admissions with an Intracerebral Hemorrhage (ICH) diagnosis
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- Filter for ICH using both ICD-9 and ICD-10 codes
      (
        icd_version = 9
        AND icd_code = '431'
      )
      OR (
        icd_version = 10
        AND icd_code LIKE 'I61%'
      )
  ),
  cohort AS (
    -- Step 2: Define the primary patient cohort: Male, 73-83 years old, with ICH
    SELECT
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    INNER JOIN
      ich_hadms AS i
      ON a.hadm_id = i.hadm_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 73 AND 83
  ),
  lab_scores AS (
    -- Step 3: Calculate instability score (count of unique abnormal lab types in first 48h)
    SELECT
      c.hadm_id,
      COUNT(DISTINCT le.itemid) AS instability_score
    FROM
      cohort AS c
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON c.hadm_id = le.hadm_id
    WHERE
      -- Filter for labs within the first 48 hours of admission
      le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
      -- Filter for labs flagged as abnormal
      AND le.flag = 'abnormal'
    GROUP BY
      c.hadm_id
  ),
  cohort_scores AS (
    -- Step 4: Assign scores to cohort, defaulting to 0 for patients with no abnormal labs
    SELECT
      c.hadm_id,
      c.admittime,
      c.dischtime,
      c.hospital_expire_flag,
      COALESCE(ls.instability_score, 0) AS instability_score
    FROM
      cohort AS c
    LEFT JOIN
      lab_scores AS ls
      ON c.hadm_id = ls.hadm_id
  ),
  cohort_quartiles AS (
    -- Step 5: Stratify the cohort into quartiles based on the instability score
    SELECT
      *,
      NTILE(4) OVER (
        ORDER BY
          instability_score
      ) AS instability_quartile
    FROM
      cohort_scores
  ),
  all_inpatients_stats AS (
    -- Step 6: Calculate benchmark statistics for ALL inpatients for comparison
    SELECT
      AVG(SAFE_DIVIDE(DATETIME_DIFF(dischtime, admittime, HOUR), 24.0)) AS overall_mean_los,
      AVG(CAST(hospital_expire_flag AS FLOAT64)) AS overall_mortality_rate
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions`
  )
-- Final Step: Aggregate metrics per quartile and join with overall stats for comparison
SELECT
  cq.instability_quartile,
  COUNT(cq.hadm_id) AS num_patients,
  MIN(cq.instability_score) AS min_score_in_quartile,
  MAX(cq.instability_score) AS max_score_in_quartile,
  AVG(
    SAFE_DIVIDE(DATETIME_DIFF(cq.dischtime, cq.admittime, HOUR), 24.0)
  ) AS mean_los_days,
  AVG(CAST(cq.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
  -- Include the overall stats for direct comparison
  all_stats.overall_mean_los,
  all_stats.overall_mortality_rate
FROM
  cohort_quartiles AS cq
CROSS JOIN
  all_inpatients_stats AS all_stats
GROUP BY
  cq.instability_quartile,
  all_stats.overall_mean_los,
  all_stats.overall_mortality_rate
ORDER BY
  cq.instability_quartile;