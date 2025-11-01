WITH eligible_patients AS (
  SELECT
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND (
          di.long_title LIKE '%acute coronary syndrome%'
          OR di.long_title LIKE '%myocardial infarction%'
          OR di.long_title LIKE '%unstable angina%'
          OR di.long_title LIKE '%ischemic heart disease%'
        )
    )
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND (
          di.long_title LIKE '%COPD%'
          OR di.long_title LIKE '%chronic obstructive pulmonary disease%'
        )
    )
)
SELECT
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los_days) AS percentile_75
FROM (
  SELECT
    DATE_DIFF(dischtime, admittime, DAY) AS los_days
  FROM
    eligible_patients
);