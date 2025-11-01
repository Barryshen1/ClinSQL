WITH sepsis_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dcd
    ON di.icd_code = dcd.icd_code
   AND di.icd_version = dcd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON di.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (LOWER(dcd.long_title) LIKE '%sepsis%' OR LOWER(dcd.long_title) LIKE '%septicemia%')
),
platelet_peaks AS (
  SELECT le.subject_id,
         MAX(le.valuenum) AS peak_platelet
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  JOIN sepsis_hadm sh
    ON le.hadm_id = sh.hadm_id
  WHERE le.valuenum IS NOT NULL
    AND (LOWER(dli.label) LIKE '%platelet%' OR LOWER(dli.label) LIKE '%platelet count%')
  GROUP BY le.subject_id
)
SELECT
  quantiles[OFFSET(74)] AS p75_peak_platelet
FROM (
  SELECT APPROX_QUANTILES(peak_platelet, 100) AS quantiles
  FROM platelet_peaks
  WHERE peak_platelet IS NOT NULL
) AS t;