SELECT
  APPROX_QUANTILES(
    DATETIME_DIFF(stoptime, starttime, HOUR), 2
  )[OFFSET(1)] AS median_duration_hours
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON pr.subject_id = pt.subject_id
WHERE
  pt.gender = 'F'
  AND pt.anchor_age BETWEEN 59 AND 69
  AND pr.hadm_id IS NOT NULL
  AND LOWER(pr.drug) IN (
    'amlodipine',
    'felodipine',
    'isradipine',
    'nicardipine',
    'nifedipine',
    'nimodipine'
  )
  AND pr.starttime IS NOT NULL
  AND pr.stoptime IS NOT NULL;