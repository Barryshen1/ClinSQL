WITH primary_ischemic_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    COALESCE(a.dischtime, a.deathtime) AS endtime,
    -- LOS in fractional days
    TIMESTAMP_DIFF(COALESCE(a.dischtime, a.deathtime), a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
    AND d.seq_num = 1  -- primary diagnosis
    AND (
      LOWER(dd.long_title) LIKE '%ischemic%'
      OR LOWER(dd.long_title) LIKE '%infarct%'
      OR LOWER(dd.long_title) LIKE '%cerebral infarction%'
    )
    AND a.admittime IS NOT NULL
    AND COALESCE(a.dischtime, a.deathtime) IS NOT NULL
)
SELECT
  COUNT(1) AS qualifying_admissions,
  ROUND(MAX(los_days), 3) AS max_hospital_los_days
FROM
  primary_ischemic_adms
WHERE
  los_days >= 0;