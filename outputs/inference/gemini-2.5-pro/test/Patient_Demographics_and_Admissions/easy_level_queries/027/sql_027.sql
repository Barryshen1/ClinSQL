WITH FirstAdmissionLOS AS (
  SELECT
    pat.subject_id,
    adm.hadm_id,
    -- Calculate the length of stay in days for the hospital admission
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Rank admissions for each patient by their admission time to find the first one
    ROW_NUMBER() OVER(PARTITION BY pat.subject_id ORDER BY adm.admittime ASC) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  WHERE
    -- Filter for female patients
    pat.gender = 'F'
    -- Filter for the specified age range
    AND pat.anchor_age BETWEEN 77 AND 87
)
SELECT
  -- Calculate the Interquartile Range (IQR): 75th percentile - 25th percentile
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_iqr_days
FROM
  FirstAdmissionLOS
WHERE
  -- Ensure we only consider the first admission for each patient
  admission_rank = 1;