WITH GiBleedHadmIds AS (
  -- Step 1: Identify the specific cohort of female patients aged 65-75
  -- with a primary/secondary diagnosis of lower GI bleeding.
  SELECT DISTINCT
    adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 65 AND 75
    -- Using seq_num <= 2 as a proxy for a diagnosis present on admission,
    -- addressing the "within first 72 hours" requirement.
    AND dx.seq_num <= 2
    AND (
      LOWER(d_dx.long_title) LIKE '%gastrointestinal hemorrhage%'
      OR LOWER(d_dx.long_title) LIKE '%melena%'
      OR LOWER(d_dx.long_title) LIKE '%hematochezia%'
    )
),
CriticalLabCounts AS (
  -- Step 2: Calculate the "lab instability score" for each admission,
  -- defined as the count of lab results flagged as 'abnormal'.
  SELECT
    hadm_id,
    COUNT(*) AS num_abnormal_labs
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE
    flag = 'abnormal'
    AND hadm_id IS NOT NULL
  GROUP BY hadm_id
),
CohortData AS (
  -- Step 3: Combine admission data, assign cohorts, and attach metrics.
  SELECT
    adm.hadm_id,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
    CASE
      WHEN gbh.hadm_id IS NOT NULL THEN 'GI Bleed Cohort (Women, 65-75)'
      ELSE 'General Inpatients'
    END AS cohort_group,
    COALESCE(clc.num_abnormal_labs, 0) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  LEFT JOIN GiBleedHadmIds AS gbh
    ON adm.hadm_id = gbh.hadm_id
  LEFT JOIN CriticalLabCounts AS clc
    ON adm.hadm_id = clc.hadm_id
  WHERE
    -- Basic data quality check for valid admission/discharge times
    adm.dischtime >= adm.admittime
)
-- Step 4: Aggregate the results to compare the two cohorts and calculate all final metrics.
SELECT
  cohort_group,
  COUNT(hadm_id) AS number_of_admissions,
  AVG(lab_instability_score) AS critical_lab_event_frequency,
  -- Calculate 25th percentile of the score ONLY for the specified GI Bleed cohort
  APPROX_QUANTILES(
    IF(cohort_group = 'GI Bleed Cohort (Women, 65-75)', lab_instability_score, NULL), 100 IGNORE NULLS
  )[OFFSET(25)] AS lab_instability_score_25th_percentile,
  AVG(los_days) AS average_los_days,
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(hadm_id)) * 100 AS mortality_rate_percent
FROM CohortData
GROUP BY cohort_group
ORDER BY cohort_group DESC;