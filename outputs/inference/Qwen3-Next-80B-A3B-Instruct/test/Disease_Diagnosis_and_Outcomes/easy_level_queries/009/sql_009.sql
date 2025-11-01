WITH eligible_patients AS (
  SELECT DISTINCT
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON a.hadm_id = d1.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d1_desc
    ON d1.icd_code = d1_desc.icd_code AND d1.icd_version = d1_desc.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON a.hadm_id = d2.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2_desc
    ON d2.icd_code = d2_desc.icd_code AND d2.icd_version = d2_desc.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND (
      LOWER(d1_desc.long_title) LIKE '%ischemic heart disease%'
      OR LOWER(d1_desc.long_title) LIKE '%acute coronary syndrome%'
      OR LOWER(d1_desc.long_title) LIKE '%myocardial infarction%'
      OR d1.icd_code LIKE 'I20%'
      OR d1.icd_code LIKE 'I21%'
      OR d1.icd_code LIKE 'I22%'
      OR d1.icd_code LIKE 'I23%'
      OR d1.icd_code LIKE 'I24%'
      OR d1.icd_code LIKE 'I25%'
    )
    AND (
      LOWER(d2_desc.long_title) LIKE '%chronic obstructive pulmonary disease%'
      OR LOWER(d2_desc.long_title) LIKE '%copd%'
      OR d2.icd_code LIKE 'J44%'
    )
)
SELECT APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days
FROM eligible_patients;