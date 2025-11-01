SELECT
  STDDEV_SAMP(los_days) AS sd_los_days
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND d.seq_num = 1
    AND (
      -- ICD-9 hemorrhagic stroke
      (d.icd_version = 9 AND (
          d.icd_code LIKE '430%' OR
          d.icd_code LIKE '431%' OR
          d.icd_code LIKE '432%'
      ))
      OR
      -- ICD-10 hemorrhagic stroke
      (d.icd_version = 10 AND (
          d.icd_code LIKE 'I60%' OR
          d.icd_code LIKE 'I61%' OR
          d.icd_code LIKE 'I62%'
      ))
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
;