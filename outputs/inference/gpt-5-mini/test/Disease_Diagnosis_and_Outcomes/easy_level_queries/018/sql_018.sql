SELECT
  STDDEV_SAMP(length_days) AS sd_los_days,
  COUNT(*) AS n_admissions,
  AVG(length_days) AS mean_los_days
FROM (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS length_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND di.seq_num = 1  -- primary diagnosis
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
    AND (
      -- match by diagnosis description when available
      (d.long_title IS NOT NULL
        AND (
          LOWER(d.long_title) LIKE '%hemorrhag%' OR
          LOWER(d.long_title) LIKE '%haemorrhag%' OR
          LOWER(d.long_title) LIKE '%intracerebral%' OR
          LOWER(d.long_title) LIKE '%subarachnoid%'
        )
      )
      -- OR match common ICD-10 hemorrhagic stroke code patterns (I60-I62)
      OR UPPER(CAST(di.icd_code AS STRING)) LIKE 'I60%' OR UPPER(CAST(di.icd_code AS STRING)) LIKE 'I61%' OR UPPER(CAST(di.icd_code AS STRING)) LIKE 'I62%'
      -- OR match common ICD-9 hemorrhagic codes (430, 431, 432.*)
      OR di.icd_code IN ('430','431')
      OR di.icd_code LIKE '432%'
    )
)
;