WITH
-- 1. Identify all male patients in the target age range at admission
patients_base AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission using anchor_age and the year of admission
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
),
age_filtered_base AS (
  SELECT
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag
  FROM
    patients_base
  WHERE
    age_at_admission BETWEEN 52 AND 62
),
-- 2. Find all hospital admissions associated with an asthma exacerbation diagnosis
asthma_hadm_ids AS (
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code IN (
      -- ICD-9 codes for asthma with exacerbation
      '49301', '49311', '49391', '49321',
      -- ICD-10 codes for asthma with exacerbation
      'J4521', 'J4531', 'J4541', 'J4551', 'J45901'
    )
),
-- 3. Calculate the lab instability score (count of abnormal labs in first 72h) for all relevant patients
lab_scores AS (
  SELECT
    base.hadm_id,
    COUNT(le.labevent_id) AS lab_instability_score
  FROM
    age_filtered_base AS base
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON base.hadm_id = le.hadm_id
  WHERE
    le.flag = 'abnormal'
    AND le.charttime BETWEEN base.admittime AND TIMESTAMP_ADD(base.admittime, INTERVAL 72 HOUR)
  GROUP BY
    base.hadm_id
),
-- 4. Combine base patient data with scores and categorize into Asthma vs Control
all_cohorts_with_scores AS (
  SELECT
    base.hadm_id,
    base.hospital_expire_flag,
    DATETIME_DIFF(base.dischtime, base.admittime, HOUR) / 24.0 AS los_days,
    COALESCE(ls.lab_instability_score, 0) AS lab_instability_score,
    CASE
      WHEN base.hadm_id IN (SELECT hadm_id FROM asthma_hadm_ids) THEN 'Asthma'
      ELSE 'Control'
    END AS cohort_type
  FROM
    age_filtered_base AS base
  LEFT JOIN
    lab_scores AS ls
    ON base.hadm_id = ls.hadm_id
),
-- 5. Calculate the 90th percentile score for the asthma cohort, which answers the first part of the question.
asthma_p90 AS (
  SELECT
    APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(90)] AS p90_score
  FROM
    all_cohorts_with_scores
  WHERE
    cohort_type = 'Asthma'
),
-- 6. Define the final groups for comparison: Top Decile Asthma vs. Control
final_groups AS (
  SELECT
    *,
    CASE
      WHEN cohort_type = 'Asthma' AND lab_instability_score >= (SELECT p90_score FROM asthma_p90)
        THEN 'Top Decile Asthma (52-62yo Male)'
      WHEN cohort_type = 'Control'
        THEN 'Age-Matched Control (52-62yo Male, non-Asthma)'
      ELSE NULL
    END AS report_group
  FROM
    all_cohorts_with_scores
)
-- 7. Final aggregation and reporting
SELECT
  report_group,
  COUNT(hadm_id) AS number_of_patients,
  AVG(lab_instability_score) AS avg_critical_lab_events_72h,
  AVG(los_days) AS mean_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate_percent
FROM
  final_groups
WHERE
  report_group IS NOT NULL
GROUP BY
  report_group
ORDER BY
  report_group DESC;