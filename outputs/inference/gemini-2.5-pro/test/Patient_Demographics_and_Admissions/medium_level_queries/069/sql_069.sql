WITH first_service AS (
  -- Identify the first service for each hospital admission to determine if it's a medical admission
  SELECT
    hadm_id,
    curr_service,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.services`
),
cohort AS (
  -- Define the patient cohort based on the specified criteria
  SELECT
    adm.hadm_id,
    adm.hospital_expire_flag,
    -- Calculate precise length of stay in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    first_service
    ON adm.hadm_id = first_service.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND adm.admission_type = 'EMERGENCY'
    AND first_service.rn = 1 -- Ensure we are looking at the initial service
    AND first_service.curr_service = 'MED' -- Filter for medical admissions
    AND adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL -- Exclude admissions with invalid time stamps
),
cohort_metrics AS (
  -- Calculate the proportion of patients with LOS >= 7 days, grouped by outcome
  SELECT
    hospital_expire_flag,
    SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(*)) AS proportion_los_ge_7
  FROM
    cohort
  GROUP BY
    hospital_expire_flag
),
percentile_calc AS (
  -- Calculate the percentile rank of a 7-day LOS for the entire cohort.
  -- This is the proportion of patients with LOS < 7 days.
  SELECT
    SAFE_DIVIDE(COUNTIF(los_days < 7), COUNT(*)) AS percentile_rank_of_7_day_los
  FROM
    cohort
)
-- Final query to combine the results and present them clearly
SELECT
  CASE
    WHEN cm.hospital_expire_flag = 0
      THEN 'Discharged Alive'
    WHEN cm.hospital_expire_flag = 1
      THEN 'In-Hospital Mortality'
  END AS outcome,
  cm.proportion_los_ge_7,
  pc.percentile_rank_of_7_day_los
FROM
  cohort_metrics AS cm,
  percentile_calc AS pc
ORDER BY
  outcome DESC;