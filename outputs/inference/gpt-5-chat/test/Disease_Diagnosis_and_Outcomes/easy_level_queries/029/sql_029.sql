WITH female_seniors AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
),
ugib_admissions AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%gastrointest%' 
    AND (
      LOWER(dd.long_title) LIKE '%upper%' 
      OR LOWER(dd.long_title) LIKE '%duodenal%' 
      OR LOWER(dd.long_title) LIKE '%gastric%' 
      OR LOWER(dd.long_title) LIKE '%esophageal%'
    )
    AND LOWER(dd.long_title) LIKE '%hemorrhage%'
),
copd_exac_admissions AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%chronic obstructive%'
    AND LOWER(dd.long_title) LIKE '%exacerbation%'
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days
FROM (
  SELECT
    fs.subject_id,
    fs.hadm_id,
    TIMESTAMP_DIFF(fs.dischtime, fs.admittime, HOUR) / 24.0 AS los_days
  FROM female_seniors fs
  JOIN ugib_admissions u
    ON fs.hadm_id = u.hadm_id
  JOIN copd_exac_admissions c
    ON fs.hadm_id = c.hadm_id
);