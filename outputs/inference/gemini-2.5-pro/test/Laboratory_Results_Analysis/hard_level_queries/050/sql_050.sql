WITH
  -- Step 1: Identify all hospital admissions with an ARDS diagnosis
  ards_hadm AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      icd_code IN ('J80', '518.82') -- J80 is ARDS in ICD-10, 518.82 is ARDS in ICD-9
  ),

  -- Step 2: Create a base cohort of female patients aged 40-50 and flag ARDS cases
  base_cohort AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      CASE
        WHEN ards.hadm_id IS NOT NULL THEN 1
        ELSE 0
      END AS is_ards
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    LEFT JOIN
      ards_hadm AS ards
      ON a.hadm_id = ards.hadm_id
    WHERE
      p.gender = 'F'
      AND (
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age
      ) BETWEEN 40 AND 50
  ),

  -- Step 3: Calculate the lab instability score (count of abnormal labs in first 72h) for all patients
  lab_instability_scores AS (
    SELECT
      bc.hadm_id,
      COUNT(le.labevent_id) AS lab_instability_score
    FROM
      base_cohort AS bc
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON bc.hadm_id = le.hadm_id
    WHERE
      le.flag = 'abnormal'
      AND le.charttime <= DATETIME_ADD(bc.admittime, INTERVAL 72 HOUR)
    GROUP BY
      bc.hadm_id
  ),

  -- Step 4: Join ARDS patients with their scores
  ards_cohort_with_scores AS (
    SELECT
      bc.hadm_id,
      bc.hospital_expire_flag,
      DATETIME_DIFF(bc.dischtime, bc.admittime, DAY) AS los_days,
      COALESCE(lis.lab_instability_score, 0) AS lab_instability_score
    FROM
      base_cohort AS bc
    LEFT JOIN
      lab_instability_scores AS lis
      ON bc.hadm_id = lis.hadm_id
    WHERE
      bc.is_ards = 1
  ),

  -- Step 5: Calculate the 75th percentile score for the ARDS cohort to define the threshold
  score_threshold AS (
    SELECT
      APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(75)] AS score_75th_percentile
    FROM
      ards_cohort_with_scores
  ),

  -- Step 6: Analyze the high-risk ARDS group (patients at/above the threshold)
  high_risk_ards_analysis AS (
    SELECT
      AVG(aws.hospital_expire_flag) AS mortality_rate_high_risk_ards,
      AVG(aws.los_days) AS mean_los_high_risk_ards,
      AVG(aws.lab_instability_score) AS avg_critical_labs_high_risk_ards
    FROM
      ards_cohort_with_scores AS aws,
      score_threshold AS st
    WHERE
      aws.lab_instability_score >= st.score_75th_percentile
  ),

  -- Step 7: Analyze the non-ARDS control group to find their average score
  non_ards_analysis AS (
    SELECT
      AVG(COALESCE(lis.lab_instability_score, 0)) AS avg_critical_labs_non_ards
    FROM
      base_cohort AS bc
    LEFT JOIN
      lab_instability_scores AS lis
      ON bc.hadm_id = lis.hadm_id
    WHERE
      bc.is_ards = 0
  )

-- Step 8: Combine all results into a final report
SELECT
  st.score_75th_percentile,
  hr.mortality_rate_high_risk_ards,
  hr.mean_los_high_risk_ards,
  hr.avg_critical_labs_high_risk_ards,
  na.avg_critical_labs_non_ards
FROM
  high_risk_ards_analysis AS hr,
  non_ards_analysis AS na,
  score_threshold AS st;