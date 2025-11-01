WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
),
high_intensity_atorvastatin AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.dose_val_rx,
    pr.dose_unit_rx,
    pr.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE
    LOWER(pr.drug) LIKE '%atorvastatin%'
    AND LOWER(pr.dose_val_rx) IN ('40', '80', '40-80')
    AND LOWER(pr.dose_unit_rx) = 'mg'
),
rx_with_duration AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    hi.drug,
    hi.dose_val_rx,
    hi.starttime,
    -- Use stoptime if available, else use dischtime
    COALESCE(hi.stoptime, c.dischtime) AS endtime,
    DATE_DIFF(CAST(COALESCE(hi.stoptime, c.dischtime) AS DATE), CAST(hi.starttime AS DATE), DAY) AS duration_days
  FROM
    cohort c
    INNER JOIN high_intensity_atorvastatin hi
      ON c.subject_id = hi.subject_id
      AND c.hadm_id = hi.hadm_id
  WHERE
    hi.starttime IS NOT NULL
    AND COALESCE(hi.stoptime, c.dischtime) IS NOT NULL
)
SELECT
  MIN(duration_days) AS min_high_intensity_atorvastatin_days
FROM
  rx_with_duration
WHERE
  duration_days > 0;