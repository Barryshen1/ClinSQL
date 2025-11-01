SELECT
  ROUND(approx_quantiles(duration_days, 100)[OFFSET(25)], 2) AS p25_duration_days,
  COUNT(*) AS n_prescriptions_considered
FROM (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    -- Duration in fractional days (seconds / 86400)
    TIMESTAMP_DIFF(
      LEAST(COALESCE(p.stoptime, a.dischtime), a.dischtime),
      GREATEST(p.starttime, a.admittime),
      SECOND
    ) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
    AND p.hadm_id IS NOT NULL
    AND p.starttime IS NOT NULL
    -- Filter for common dihydropyridine calcium channel blockers (case-insensitive)
    AND (
      LOWER(p.drug) LIKE '%amlodipine%' OR
      LOWER(p.drug) LIKE '%nifedipine%' OR
      LOWER(p.drug) LIKE '%felodipine%' OR
      LOWER(p.drug) LIKE '%nicardipine%' OR
      LOWER(p.drug) LIKE '%isradipine%' OR
      LOWER(p.drug) LIKE '%nimodipine%' OR
      LOWER(p.drug) LIKE '%nitrendipine%' OR
      LOWER(p.drug) LIKE '%lacidipine%'
    )
    -- Ensure the computed end > start (positive duration) and start within admission window
    AND LEAST(COALESCE(p.stoptime, a.dischtime), a.dischtime) > GREATEST(p.starttime, a.admittime)
)
;