WITH female_patients_77_87 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 77 AND 87
),

dialysis_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id
  FROM
    female_patients_77_87 p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON a.hadm_id = proc.hadm_id
  WHERE
    -- Dialysis ICD-9/10 codes (partial list)
    proc.icd_code IN ('39.95', '54.98', 'Z99.2', '5A1D00Z')
),

first_icu_stays AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, DAY) + 1 AS icu_los_days,
    ROW_NUMBER() OVER (PARTITION BY d.hadm_id ORDER BY i.intime) AS icu_stay_rank
  FROM
    dialysis_patients d
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON d.hadm_id = i.hadm_id
  WHERE
    i.outtime > i.intime  -- Ensure valid time range
),

percentiles AS (
  SELECT
    APPROX_QUANTILES(icu_los_days, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(icu_los_days, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(icu_los_days, 100)[OFFSET(75)] AS q3
  FROM
    first_icu_stays
  WHERE
    icu_stay_rank = 1
)

SELECT
  q1,
  median,
  q3,
  q3 - q1 AS iqr
FROM
  percentiles;