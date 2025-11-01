WITH sepsis_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%sepsis%'
),
sepsis_patients AS (
  SELECT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN sepsis_codes sc
    ON di.icd_code = sc.icd_code AND di.icd_version = sc.icd_version
  GROUP BY di.subject_id
),
platelet_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) = 'platelets'
),
male_sepsis_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN sepsis_patients sp ON p.subject_id = sp.subject_id
  WHERE p.gender = 'M'
),
peak_platelets AS (
  SELECT 
    le.subject_id,
    MAX(le.valuenum) AS peak_platelet
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN platelet_item pi ON le.itemid = pi.itemid
  INNER JOIN male_sepsis_patients msp ON le.subject_id = msp.subject_id
  WHERE le.valuenum IS NOT NULL
  GROUP BY le.subject_id
)
SELECT
  APPROX_QUANTILES(peak_platelet, 1000)[OFFSET(750)] AS platelet_count_75th_percentile
FROM peak_platelets;