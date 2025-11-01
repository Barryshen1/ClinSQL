SELECT
  STDDEV_SAMP(los_days) AS sd_los_days,
  COUNT(*) AS n_admissions
FROM (
  SELECT
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dict
    ON di.icd_code = dict.icd_code
    AND di.icd_version = dict.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND di.seq_num = 1  -- primary diagnosis for the admission
    AND (
      LOWER(dict.long_title) LIKE '%hemorrhag%' OR
      LOWER(dict.long_title) LIKE '%haemorrh%' OR
      LOWER(dict.long_title) LIKE '%subarachnoid%' OR
      LOWER(dict.long_title) LIKE '%intracerebral%' OR
      LOWER(dict.long_title) LIKE '%intraparenchymal%'
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, SECOND) > 0
)
;