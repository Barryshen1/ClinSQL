WITH
  ap_cohort AS (
    -- Step 1: Identify male patients aged 63-73 with an Acute Pancreatitis diagnosis.
    SELECT DISTINCT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      adm.hospital_expire_flag,
      DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    WHERE
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 63 AND 73
      AND (
        (dx.icd_code = '5770' AND dx.icd_version = 9) -- Acute pancreatitis, ICD-9
        OR (dx.icd_code LIKE 'K85%' AND dx.icd_version = 10) -- Acute pancreatitis, ICD-10
      )
  ),
  lab_scores AS (
    -- Step 2: Calculate the 72-hour "lab instability score" for each patient.
    -- The score is the count of lab results flagged as 'abnormal'.
    SELECT
      cohort.hadm_id,
      cohort.hospital_expire_flag,
      cohort.los_days,
      COUNTIF(le.flag = 'abnormal') AS instability_score
    FROM ap_cohort AS cohort
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON cohort.hadm_id = le.hadm_id
    WHERE
      -- Filter labs to the first 72 hours of the hospital admission
      le.charttime BETWEEN cohort.admittime AND DATETIME_ADD(cohort.admittime, INTERVAL 72 HOUR)
    GROUP BY
      cohort.hadm_id,
      cohort.hospital_expire_flag,
      cohort.los_days
  ),
  score_percentiles AS (
    -- Step 3: Calculate the 90th percentile of the instability score across the cohort.
    SELECT
      *,
      PERCENTILE_CONT(instability_score, 0.9) OVER () AS p90_score
    FROM lab_scores
  ),
  patient_groups AS (
    -- Step 4: Categorize patients into 'P90_or_higher' or 'Below_P90' groups.
    SELECT
      hadm_id,
      instability_score,
      p90_score,
      hospital_expire_flag,
      los_days,
      CASE
        WHEN instability_score >= p90_score
        THEN 'P90_or_higher'
        ELSE 'Below_P90'
      END AS patient_group
    FROM score_percentiles
  ),
  p90_group_summary AS (
    -- Step 5: Calculate mortality, mean LOS, and the P90 threshold for the high-risk group.
    SELECT
      ROUND(MIN(p90_score), 2) AS p90_instability_score_threshold,
      ROUND(AVG(los_days), 2) AS p90_group_mean_los_days,
      ROUND(AVG(CAST(hospital_expire_flag AS NUMERIC)) * 100, 2) AS p90_group_mortality_rate_percent
    FROM patient_groups
    WHERE
      patient_group = 'P90_or_higher'
  ),
  grouped_labs AS (
    -- Step 6: Get all 72-hour labs for the cohort and link them to their patient group and lab name.
    SELECT
      pg.patient_group,
      le.itemid,
      di.label,
      le.flag
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN patient_groups AS pg
      ON le.hadm_id = pg.hadm_id
    INNER JOIN ap_cohort AS ap
      ON le.hadm_id = ap.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
      ON le.itemid = di.itemid
    WHERE
      le.charttime BETWEEN ap.admittime AND DATETIME_ADD(ap.admittime, INTERVAL 72 HOUR)
  ),
  p90_rates AS (
    -- Step 7a: Calculate per-lab critical rates for the P90+ group.
    SELECT
      itemid,
      label,
      COUNT(*) AS total_tests_p90_group,
      ROUND(COUNTIF(flag = 'abnormal') / COUNT(*), 4) AS critical_rate_p90_group
    FROM grouped_labs
    WHERE
      patient_group = 'P90_or_higher'
    GROUP BY
      itemid,
      label
  ),
  below_p90_rates AS (
    -- Step 7b: Calculate per-lab critical rates for the comparison group (<P90).
    SELECT
      itemid,
      label,
      COUNT(*) AS total_tests_below_p90_group,
      ROUND(COUNTIF(flag = 'abnormal') / COUNT(*), 4) AS critical_rate_below_p90_group
    FROM grouped_labs
    WHERE
      patient_group = 'Below_P90'
    GROUP BY
      itemid,
      label
  )
-- Final Step: Combine the summary stats with the detailed per-lab rate comparison.
SELECT
  -- Summary stats (repeated on each row for context)
  summary.p90_instability_score_threshold,
  summary.p90_group_mean_los_days,
  summary.p90_group_mortality_rate_percent,
  -- Per-lab comparison
  COALESCE(p90.label, below90.label) AS lab_test,
  p90.total_tests_p90_group,
  p90.critical_rate_p90_group,
  below90.total_tests_below_p90_group,
  below90.critical_rate_below_p90_group
FROM p90_rates AS p90
FULL OUTER JOIN below_p90_rates AS below90
  ON p90.itemid = below90.itemid
CROSS JOIN p90_group_summary AS summary
ORDER BY
  p90.total_tests_p90_group DESC,
  lab_test
LIMIT 50; -- Limiting to top 50 most common labs in the P90 group for readability;