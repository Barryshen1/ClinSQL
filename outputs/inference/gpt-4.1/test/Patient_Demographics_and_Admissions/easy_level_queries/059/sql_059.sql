SELECT
  icu.subject_id,
  icu.hadm_id,
  p.anchor_age,
  p.gender,
  MAX(icu.los) AS max_icu_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON proc.subject_id = icu.subject_id
    AND proc.hadm_id = icu.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND proc.icd_version = 10
  AND (
    proc.icd_code LIKE '0270%' OR
    proc.icd_code LIKE '0271%' OR
    proc.icd_code LIKE '0272%' OR
    proc.icd_code LIKE '0273%'
  )
GROUP BY
  icu.subject_id,
  icu.hadm_id,
  p.anchor_age,
  p.gender
ORDER BY
  max_icu_los_days DESC;