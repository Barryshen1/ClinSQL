WITH hemorrhagic_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    -- precise LOS in days (fractional)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    USING(subject_id, hadm_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE
    d.seq_num = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND (
      -- ICD-9 hemorrhagic stroke codes: 430, 431, 432...
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^(430|431|432)'))
      OR
      -- ICD-10 hemorrhagic stroke codes: I60, I61, I62...
      (d.icd_version = 10 AND REGEXP_CONTAINS(UPPER(d.icd_code), r'^(I60|I61|I62)'))
    )
)

SELECT
  COUNT(*) AS n_admissions,
  STDDEV_SAMP(los_days) AS sd_los_days
FROM
  hemorrhagic_admissions;