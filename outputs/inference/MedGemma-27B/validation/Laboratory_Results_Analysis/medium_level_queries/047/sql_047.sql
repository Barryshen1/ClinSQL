WITH PatientACS AS (
  -- Identify patients with ACS diagnosis
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND d.icd_code LIKE 'I21%' -- ACS ICD-10 codes start with I21
),
InitialTroponin AS (
  -- Get initial Troponin T values for ACS patients
  SELECT
    p.subject_id,
    a.hadm_id,
    l.charttime,
    l.valuenum AS troponin_value
  FROM PatientACS AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON a.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'Troponin T'
    AND l.charttime = (
      SELECT
        MIN(charttime)
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l2
      WHERE
        l2.subject_id = l.subject_id
        AND l2.hadm_id = l.hadm_id
        AND l2.itemid = l.itemid
    )
),
TroponinPercentile AS (
  -- Calculate the 99th percentile for Troponin T
  SELECT
    PERCENTILE_CONT(0.99, troponin_value) AS percentile_99
  FROM InitialTroponin
),
FilteredTroponin AS (
  -- Filter Troponin values above the 99th percentile
  SELECT
    it.subject_id,
    it.hadm_id,
    it.troponin_value
  FROM InitialTroponin AS it
  CROSS JOIN TroponinPercentile AS tp
  WHERE
    it.troponin_value > tp.percentile_99
)
-- Final aggregation
SELECT
  COUNT(DISTINCT ft.subject_id) AS patient_count,
  COUNT(DISTINCT ft.hadm_id) AS admission_count,
  AVG(ft.troponin_value) AS mean_troponin,
  MEDIAN(ft.troponin_value) AS median_troponin,
  PERCENTILE_CONT(0.25, ft.troponin_value) AS iqr_troponin_25,
  PERCENTILE_CONT(0.75, ft.troponin_value) AS iqr_troponin_75
FROM FilteredTroponin AS ft;