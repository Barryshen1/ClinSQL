SELECT
  STDDEV( TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 ) AS sd_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 51 AND 61
  AND d.seq_num = 1
  AND (
    -- ICD-9 hemorrhagic stroke codes
    (d.icd_version = 9 AND (
      d.icd_code LIKE '430%' OR
      d.icd_code LIKE '431%' OR
      d.icd_code LIKE '432%'
    ))
    OR
    -- ICD-10 hemorrhagic stroke codes
    (d.icd_version = 10 AND (
      d.icd_code LIKE 'I60%' OR
      d.icd_code LIKE 'I61%' OR
      d.icd_code LIKE 'I62%'
    ))
  )
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;