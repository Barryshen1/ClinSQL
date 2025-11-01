WITH patient_los AS (
  SELECT
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON adm.subject_id = p.subject_id
  INNER JOIN (
    SELECT
      di.hadm_id,
      di.icd_code,
      di.icd_version
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE
      di.seq_num = 1 -- primary diagnosis
      AND (
        (di.icd_version = 10 AND di.icd_code LIKE 'I63%') -- ICD-10 ischemic stroke
        OR (di.icd_version = 9 AND di.icd_code IN ('43401', '43411', '43491')) -- ICD-9 cerebral artery occlusion with infarction
      )
  ) AS stroke_adm
  ON adm.hadm_id = stroke_adm.hadm_id
  -- Calculate age at admission
  WHERE
    p.gender = 'F'
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
    AND DATETIME_DIFF(adm.admittime, DATE(p.anchor_year, 1, 1), YEAR) + p.anchor_age BETWEEN 71 AND 81
)
SELECT
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] - APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS iqr_los_days
FROM
  patient_los
HAVING
  COUNT(*) > 0;