WITH
  -- Step 1: Identify all female patients aged 65-75
  patients_base AS (
    SELECT
      subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'F'
      AND anchor_age BETWEEN 65 AND 75
  ),
  -- Step 2: Identify all hospital admissions for acute pancreatitis
  pancreatitis_hadms AS (
    SELECT DISTINCT
      dia.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dia
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON dia.icd_code = d.icd_code AND dia.icd_version = d.icd_version
    WHERE
      d.long_title LIKE '%Acute pancreatitis%'
  ),
  -- Step 3: Create the full cohort of admissions, flagging pancreatitis cases and calculating LOS
  cohort_admissions AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.hospital_expire_flag,
      DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
      CASE
        WHEN p.hadm_id IS NOT NULL THEN 1
        ELSE 0
      END AS is_pancreatitis
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      INNER JOIN patients_base AS pb ON adm.subject_id = pb.subject_id
      LEFT JOIN pancreatitis_hadms AS p ON adm.hadm_id = p.hadm_id
    WHERE
      adm.dischtime IS NOT NULL -- Exclude admissions without a discharge time
  ),
  -- Step 4: Calculate the lab instability score for each admission (count of abnormal labs in first 48h)
  instability_scores AS (
    SELECT
      le.hadm_id,
      COUNT(*) AS instability_score
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON le.hadm_id = adm.hadm_id
    WHERE
      le.flag = 'abnormal'
      AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 48 HOUR)
    GROUP BY
      le.hadm_id
  ),
  -- Step 5: Combine cohort data with instability scores
  full_cohort_data AS (
    SELECT
      ca.hadm_id,
      ca.is_pancreatitis,
      ca.los_days,
      ca.hospital_expire_flag,
      COALESCE(isc.instability_score, 0) AS instability_score
    FROM
      cohort_admissions AS ca
      LEFT JOIN instability_scores AS isc ON ca.hadm_id = isc.hadm_id
  ),
  -- Step 6: Calculate the comparison metric for the control group
  comparison_metric AS (
    SELECT
      AVG(
        CASE
          WHEN instability_score > 0 THEN 1.0
          ELSE 0.0
        END
      ) * 100 AS control_pct_with_critical_labs
    FROM full_cohort_data
    WHERE
      is_pancreatitis = 0
  ),
  -- Step 7: Analyze the pancreatitis cohort, assign quintiles, and calculate the group's overall metric
  pancreatitis_quintiles AS (
    SELECT
      hadm_id,
      instability_score,
      los_days,
      hospital_expire_flag,
      -- Calculate pancreatitis group's overall % with critical labs using a window function
      AVG(
        CASE
          WHEN instability_score > 0 THEN 1.0
          ELSE 0.0
        END
      ) OVER () * 100 AS pancreatitis_pct_with_critical_labs,
      -- Assign quintiles based on the score
      NTILE(5) OVER (
        ORDER BY
          instability_score
      ) AS score_quintile
    FROM full_cohort_data
    WHERE
      is_pancreatitis = 1
  )
-- Final Step: Aggregate results by quintile and join the comparison metrics
SELECT
  pq.score_quintile,
  COUNT(pq.hadm_id) AS patient_count,
  AVG(pq.instability_score) AS mean_instability_score,
  AVG(pq.los_days) AS mean_los_days,
  AVG(pq.hospital_expire_flag) AS mortality_rate,
  MAX(pq.pancreatitis_pct_with_critical_labs) AS pancreatitis_group_percent_with_critical_labs,
  MAX(cm.control_pct_with_critical_labs) AS control_group_percent_with_critical_labs
FROM
  pancreatitis_quintiles AS pq,
  comparison_metric AS cm -- Cross join the single-row comparison metric
GROUP BY
  pq.score_quintile
ORDER BY
  pq.score_quintile;