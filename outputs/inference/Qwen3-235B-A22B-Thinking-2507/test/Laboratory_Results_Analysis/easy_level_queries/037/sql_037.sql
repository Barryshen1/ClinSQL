WITH sepsis_admissions AS (
  SELECT DISTINCT di.hadm_id, di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.icd_version = 10
    AND di.icd_code IN (
      'A40.0', 'A40.1', 'A40.2', 'A40.3', 'A40.8', 'A40.9',
      'A41.0', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.8', 'A41.9',
      'R65.20', 'R65.21'
    )
),
male_sepsis AS (
  SELECT sa.hadm_id, sa.subject_id
  FROM sepsis_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON sa.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
platelet_counts AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS platelet_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.label = 'Platelets'
    AND le.valuenum IS NOT NULL
),
admission_peaks AS (
  SELECT 
    ms.hadm_id,
    ms.subject_id,
    MAX(pc.platelet_count) AS max_platelet
  FROM male_sepsis ms
  LEFT JOIN platelet_counts pc
    ON ms.hadm_id = pc.hadm_id
  GROUP BY ms.hadm_id, ms.subject_id
),
patient_peaks AS (
  SELECT
    subject_id,
    MAX(max_platelet) AS peak_platelet
  FROM admission_peaks
  GROUP BY subject_id
  HAVING peak_platelet IS NOT NULL
)
SELECT
  APPROX_QUANTILES(peak_platelet, 1000)[OFFSET(750)] AS p75_platelet
FROM patient_peaks;