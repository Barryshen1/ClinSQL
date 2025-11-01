WITH hf_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND LOWER(dd.long_title) LIKE '%heart failure%'
),
first_admissions AS (
  SELECT subject_id,
         hadm_id,
         admittime,
         dischtime,
         DATE_DIFF(dischtime, admittime, DAY) AS los_days,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM hf_patients
)
SELECT
  q[2] AS Q1,  -- index 2 for quartiles array: [min, Q1, median, Q3, max]
  q[4] AS Q3,
  q[4] - q[2] AS IQR_days
FROM (
  SELECT APPROX_QUANTILES(los_days, 4) AS q
  FROM first_admissions
  WHERE rn = 1
    AND los_days IS NOT NULL
    AND los_days >= 0
);