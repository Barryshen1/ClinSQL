SELECT
  ROUND(AVG(los_days), 2) AS avg_hospital_los_days
FROM (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    -- UGIB diagnosis
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON
        d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%gastrointestinal hemorrhage%'
    )
    -- COPD exacerbation diagnosis
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2
      ON
        d2.icd_code = dd2.icd_code
        AND d2.icd_version = dd2.icd_version
      WHERE
        d2.hadm_id = a.hadm_id
        AND LOWER(dd2.long_title) LIKE '%chronic obstructive pulmonary disease%'
        AND LOWER(dd2.long_title) LIKE '%exacerbation%'
    )
);