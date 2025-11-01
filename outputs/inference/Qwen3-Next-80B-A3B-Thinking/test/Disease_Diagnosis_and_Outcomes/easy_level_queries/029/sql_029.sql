WITH qualifying_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND (
          di.long_title LIKE '%upper gastrointestinal hemorrhage%'
          OR di.long_title LIKE '%upper GI bleed%'
          OR di.long_title LIKE '%gastrointestinal hemorrhage, upper%'
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND (
          di.long_title LIKE '%COPD exacerbation%'
          OR di.long_title LIKE '%chronic obstructive pulmonary disease with acute exacerbation%'
        )
    )
)
SELECT
  PERCENTILE_CONT(los_days, 0.5) OVER () AS median_los
FROM (
  SELECT
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM
    qualifying_admissions
)
LIMIT 1;