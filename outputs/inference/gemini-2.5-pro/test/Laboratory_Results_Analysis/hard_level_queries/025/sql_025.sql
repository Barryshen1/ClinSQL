WITH
-- Step 1: Define the primary cohort of female patients aged 48-58 with hemorrhagic stroke.
HemorrhagicStrokeCohort AS (
  SELECT DISTINCT -- Use DISTINCT to avoid duplication from multiple diagnosis codes per admission
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON a.hadm_id = dx.hadm_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 48 AND 58
    -- Filter for hemorrhagic stroke using both ICD-9 and ICD-10 codes
    AND (
      (dx.icd_version = 9 AND (dx.icd_code LIKE '430%' OR dx.icd_code LIKE '431%' OR dx.icd_code LIKE '432%'))
      OR
      (dx.icd_version = 10 AND (dx.icd_code LIKE 'I60%' OR dx.icd_code LIKE 'I61%' OR dx.icd_code LIKE 'I62%'))
    )
),

-- Step 2: Calculate lab instability score and total critical labs for each patient in the cohort.
PatientLabScores AS (
  SELECT
    hsc.hadm_id,
    hsc.hospital_expire_flag,
    hsc.los_days,
    -- Use COALESCE to assign a score of 0 to patients with no critical labs.
    COALESCE(cl.lab_instability_score, 0) AS lab_instability_score,
    COALESCE(cl.num_critical_labs, 0) AS num_critical_labs
  FROM
    HemorrhagicStrokeCohort AS hsc
  LEFT JOIN (
    -- Subquery to find abnormal labs within the first 72 hours and calculate scores
    SELECT
      le.hadm_id,
      COUNT(DISTINCT dli.category) AS lab_instability_score, -- Count of unique lab systems
      COUNT(le.labevent_id) AS num_critical_labs -- Count of all critical lab events
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
      ON le.itemid = dli.itemid
    -- Ensure we only consider labs for patients in our cohort
    INNER JOIN
      HemorrhagicStrokeCohort AS hsc_inner
      ON le.hadm_id = hsc_inner.hadm_id
    WHERE
      le.flag = 'abnormal'
      AND le.charttime BETWEEN hsc_inner.admittime AND DATETIME_ADD(hsc_inner.admittime, INTERVAL 72 HOUR)
    GROUP BY
      le.hadm_id
  ) AS cl
    ON hsc.hadm_id = cl.hadm_id
),

-- Step 3: Calculate the 90th percentile of the lab instability score.
P90_Score AS (
  SELECT
    APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(90)] AS p90_value
  FROM
    PatientLabScores
)

-- Step 4: Final aggregation to compare the high-instability group vs. the control group.
SELECT
  CASE
    WHEN pls.lab_instability_score >= p90.p90_value
    THEN 'High-Instability (>=P90)'
    ELSE 'Control (<P90)'
  END AS cohort_group,
  p90.p90_value AS p90_lab_instability_score,
  COUNT(pls.hadm_id) AS num_patients,
  -- Calculate mortality rate, mean LOS, and average critical labs for each group.
  ROUND(AVG(pls.hospital_expire_flag) * 100, 2) AS mortality_rate_percent,
  ROUND(AVG(pls.los_days), 2) AS mean_los_days,
  ROUND(AVG(pls.num_critical_labs), 2) AS avg_critical_labs_per_patient
FROM
  PatientLabScores AS pls,
  P90_Score AS p90 -- Cross-join to make the P90 value available for comparison.
GROUP BY
  cohort_group,
  p90_lab_instability_score
ORDER BY
  -- Display the High-Instability group first for easier comparison.
  cohort_group DESC;