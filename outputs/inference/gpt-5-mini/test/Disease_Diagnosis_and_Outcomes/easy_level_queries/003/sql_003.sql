WITH eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- LOS in days with fractional part
    TIMESTAMP_DIFF(TIMESTAMP(a.dischtime), TIMESTAMP(a.admittime), SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  USING(subject_id, hadm_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
  ON
    d.icd_code = dicd.icd_code
    AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND d.seq_num = 1  -- primary diagnosis for the admission
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(TIMESTAMP(a.dischtime), TIMESTAMP(a.admittime), SECOND) >= 0
    -- match common ischemic heart disease / ACS / MI / unstable angina terms in diagnosis description
    AND (
      LOWER(dicd.long_title) LIKE '%ischemic heart%'
      OR LOWER(dicd.long_title) LIKE '%acute myocardial infarction%'
      OR LOWER(dicd.long_title) LIKE '%myocardial infarction%'
      OR LOWER(dicd.long_title) LIKE '%acute coronary%'
      OR LOWER(dicd.long_title) LIKE '%acute coronary syndrome%'
      OR LOWER(dicd.long_title) LIKE '%unstable angina%'
      OR LOWER(dicd.long_title) LIKE '%angina pectoris%'
      OR LOWER(dicd.long_title) LIKE '%coronary atherosclerosis%'
      OR LOWER(dicd.long_title) LIKE '%coronary artery%'
    )
)
SELECT
  -- 25th percentile (approximate) of hospital LOS in days
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los_days,
  COUNT(*) AS n_admissions
FROM
  eligible_admissions;