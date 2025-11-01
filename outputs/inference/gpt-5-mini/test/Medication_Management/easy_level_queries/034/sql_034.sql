SELECT
  p.subject_id,
  p.hadm_id,
  p.drug,
  TIMESTAMP_DIFF(
    LEAST(COALESCE(p.stoptime, a.dischtime), a.dischtime),
    GREATEST(p.starttime, a.admittime),
    DAY
  ) AS duration_days,
  pat.anchor_age
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON p.subject_id = pat.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.hadm_id = a.hadm_id AND p.subject_id = a.subject_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 51 AND 61
  AND p.hadm_id IS NOT NULL
  AND (
    LOWER(p.drug) LIKE '%hydralazine%' 
    OR LOWER(p.drug) LIKE '%isosorbide dinitrate%'
  )
  -- ensure there is inpatient overlap between prescription and admission
  AND LEAST(COALESCE(p.stoptime, a.dischtime), a.dischtime) > GREATEST(p.starttime, a.admittime)
ORDER BY
  duration_days DESC
LIMIT 1;