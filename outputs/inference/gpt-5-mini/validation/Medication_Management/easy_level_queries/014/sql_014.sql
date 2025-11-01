WITH presc AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    r.starttime AS presc_start,
    r.stoptime AS presc_stop,
    -- bound prescription to admission window
    GREATEST(r.starttime, a.admittime) AS bounded_start,
    LEAST(COALESCE(r.stoptime, a.dischtime), a.dischtime) AS bounded_end,
    -- duration in days (integer days between dates)
    DATE_DIFF(
      DATE(LEAST(COALESCE(r.stoptime, a.dischtime), a.dischtime)),
      DATE(GREATEST(r.starttime, a.admittime)),
      DAY
    ) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` r
    ON p.subject_id = r.subject_id
    AND a.hadm_id = r.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    -- medication is atorvastatin (case-insensitive match)
    AND LOWER(COALESCE(r.drug, '')) LIKE '%atorvastatin%'
    -- dose value between 40 and 80 (cast to numeric to avoid STRING vs INT issues)
    AND SAFE_CAST(r.dose_val_rx AS FLOAT64) IS NOT NULL
    AND SAFE_CAST(r.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    -- dose unit contains mg
    AND LOWER(COALESCE(r.dose_unit_rx, '')) LIKE '%mg%'
    -- ensure bounded times are valid (start & end exist and end >= start)
    AND r.starttime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND COALESCE(r.stoptime, a.dischtime) IS NOT NULL
    AND LEAST(COALESCE(r.stoptime, a.dischtime), a.dischtime) >= GREATEST(r.starttime, a.admittime)
)
SELECT
  MIN(duration_days) AS min_duration_days,
  COUNT(*) AS total_matching_prescriptions,
  COUNT(DISTINCT hadm_id) AS distinct_admissions_with_high_intensity_atorvastatin
FROM presc;