WITH admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
)

SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los
FROM (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM admissions
  WHERE
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = admissions.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'K25%'  -- UGIB
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = admissions.hadm_id
        AND d.icd_version = 10
        AND (d.icd_code = 'J44.0' OR d.icd_code = 'J44.1')  -- COPD exacerbation
    )
);