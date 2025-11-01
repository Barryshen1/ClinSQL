SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] AS p75_duration_days,
  COUNT(*) AS n_arb_prescriptions,
  COUNT(DISTINCT subject_id) AS n_unique_patients
FROM (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    SAFE_DIVIDE(TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND), 86400.0) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    USING (subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    USING (hadm_id, subject_id)
  WHERE
    pt.gender = 'M'
    AND pt.anchor_age BETWEEN 38 AND 48
    AND p.hadm_id IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    -- ensure the prescription was given during the hospital admission window
    AND p.starttime >= a.admittime
    AND p.starttime <= a.dischtime
    -- match common ARB generic names (case-insensitive)
    AND REGEXP_CONTAINS(LOWER(IFNULL(p.drug, '')), r'losartan|valsartan|irbesartan|candesartan|olmesartan|telmisartan|eprosartan|azilsartan')
    -- ensure non-negative duration
    AND TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) >= 0
);