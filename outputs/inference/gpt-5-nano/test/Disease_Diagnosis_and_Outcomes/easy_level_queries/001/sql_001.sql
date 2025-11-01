WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    -- hospital length of stay in days (as a float)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS LOS_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND a.dischtime > a.admittime
    -- UGIB present in this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          dd.long_title LIKE '%Upper Gastrointestinal Bleeding%'
          OR dd.long_title LIKE '%Upper GI Bleeding%'
          OR dd.long_title LIKE '%Gastrointestinal Bleeding%'
        )
    )
    -- COPD exacerbation present in this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd2
        ON di2.icd_code = dd2.icd_code
       AND di2.icd_version = dd2.icd_version
      WHERE di2.subject_id = a.subject_id
        AND di2.hadm_id = a.hadm_id
        AND (
          dd2.long_title LIKE '%Acute Exacerbation of Chronic Obstructive Pulmonary Disease%'
          OR dd2.long_title LIKE '%Chronic Obstructive Pulmonary Disease%Exacerbation%'
          OR dd2.long_title LIKE '%Chronic Obstructive Pulmonary Disease Exacerbation%'
        )
    )
)
SELECT AVG(LOS_days) AS avg_hospital_los_days
FROM eligible_admissions;