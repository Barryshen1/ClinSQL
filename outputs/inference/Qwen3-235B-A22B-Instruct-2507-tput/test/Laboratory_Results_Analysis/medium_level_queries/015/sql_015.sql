WITH female_88_98 AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
),
acs_admissions AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I24%')
    AND di.icd_version = 10
),
troponin_t_first AS (
  SELECT 
    le.hadm_id,
    MIN(le.charttime) AS first_troponin_time
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE LOWER(dli.label) LIKE '%troponin%t%'
    AND dli.fluid = 'Blood'
    AND le.valuenum IS NOT NULL
  GROUP BY le.hadm_id
),
first_troponin_values AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS first_troponin_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  INNER JOIN troponin_t_first ttf
    ON le.hadm_id = ttf.hadm_id AND le.charttime = ttf.first_troponin_time
  WHERE LOWER(dli.label) LIKE '%troponin%t%'
    AND dli.fluid = 'Blood'
    AND le.valuenum IS NOT NULL
)
SELECT
  APPROX_QUANTILES(ftv.first_troponin_value, 1000)[OFFSET(500)] AS median_troponin_t,
  APPROX_QUANTILES(ftv.first_troponin_value, 1000)[OFFSET(250)] AS q1_troponin_t,
  APPROX_QUANTILES(ftv.first_troponin_value, 1000)[OFFSET(750)] AS q3_troponin_t
FROM first_troponin_values ftv
INNER JOIN acs_admissions aa ON ftv.hadm_id = aa.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON aa.hadm_id = a.hadm_id
INNER JOIN female_88_98 f ON a.subject_id = f.subject_id
WHERE ftv.first_troponin_value > 0.01;