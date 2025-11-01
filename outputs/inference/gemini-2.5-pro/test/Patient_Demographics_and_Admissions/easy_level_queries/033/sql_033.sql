WITH dialysis_admissions AS (
  -- First, identify all unique hospital admissions (hadm_id) that included a dialysis procedure.
  -- This is done by checking the long title of procedures in d_icd_procedures.
  SELECT DISTINCT
    picd.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS picd
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON picd.icd_code = d.icd_code
    AND picd.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%dialysis%'
),

filtered_admissions AS (
  -- Next, filter these admissions to the specific patient cohort: male patients aged 44-54.
  -- We also calculate the length of stay (LOS) for each qualifying admission.
  SELECT
    -- Calculate length of stay in fractional days for better precision in the standard deviation calculation.
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON adm.subject_id = p.subject_id
  -- We use an INNER JOIN to ensure we only consider admissions that had a dialysis procedure.
  INNER JOIN
    dialysis_admissions AS da
    ON adm.hadm_id = da.hadm_id
  WHERE
    p.gender = 'M'
    -- Calculate age at the time of admission and filter for the 44-54 range.
    AND (DATETIME_DIFF(adm.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age) BETWEEN 44 AND 54
    -- Ensure the discharge time is after the admission time to get a valid, positive LOS.
    AND adm.dischtime > adm.admittime
)

-- Finally, calculate the sample standard deviation of the length of stay for the filtered group.
SELECT
  STDDEV_SAMP(los_days) AS sd_los_days
FROM
  filtered_admissions;