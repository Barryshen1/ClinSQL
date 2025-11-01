WITH ami_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I21', 'I22'))
    OR (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '410')
  )
),
ami_admissions AS (
  SELECT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN ami_codes ac
    ON di.icd_code = ac.icd_code AND di.icd_version = di.icd_version
),
hs_tnt_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t high sensitivity%'
),
first_tnt AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN hs_tnt_item hti ON le.itemid = hti.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.valuenum > 0
),
first_tnt_filtered AS (
  SELECT ft.subject_id, ft.hadm_id, ft.valuenum
  FROM first_tnt ft
  WHERE ft.rn = 1
),
patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 55 AND 65
),
qualified_patients AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    ft.valuenum AS first_tnt_value
  FROM patient_admissions pa
  INNER JOIN ami_admissions aa
    ON pa.subject_id = aa.subject_id AND pa.hadm_id = aa.hadm_id
  INNER JOIN first_tnt_filtered ft
    ON pa.subject_id = ft.subject_id AND pa.hadm_id = ft.hadm_id
  WHERE ft.valuenum > 0.01
)
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  AVG(first_tnt_value) AS mean_first_tnt,
  APPROX_QUANTILES(first_tnt_value, 100)[OFFSET(50)] AS median_first_tnt,
  APPROX_QUANTILES(first_tnt_value, 100)[OFFSET(25)] AS q1_first_tnt,
  APPROX_QUANTILES(first_tnt_value, 100)[OFFSET(75)] AS q3_first_tnt
FROM qualified_patients;