WITH chest_pain_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%chest pain%'
    AND icd_version = 10
),
patients_with_chest_pain AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  INNER JOIN chest_pain_codes cpc
    ON di.icd_code = cpc.icd_code
),
age_filtered_patients AS (
  SELECT p.subject_id, p.anchor_age, p.anchor_year, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (a.admittime BETWEEN DATETIME(p.anchor_year, 1, 1, 0, 0, 0) 
                        AND DATETIME(p.anchor_year + 1, 1, 1, 0, 0, 0))
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 64 AND 74
),
troponin_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) = 'troponin t high sensitive'
),
first_troponin AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN troponin_item ti ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
    AND LOWER(le.valueuom) IN ('ng/ml', 'mcg/l') -- assuming 1 ng/mL = 1 mcg/L
),
first_elevated_troponin AS (
  SELECT ft.subject_id, ft.hadm_id
  FROM first_troponin ft
  WHERE ft.rn = 1
    AND ft.valuenum > 0.014 -- 99th percentile for men
),
cohort AS (
  SELECT 
    afp.subject_id,
    afp.hadm_id,
    a.hospital_expire_flag
  FROM age_filtered_patients afp
  INNER JOIN patients_with_chest_pain pcp
    ON afp.subject_id = pcp.subject_id AND afp.hadm_id = pcp.hadm_id
  INNER JOIN first_elevated_troponin fet
    ON afp.subject_id = fet.subject_id AND afp.hadm_id = fet.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON afp.hadm_id = a.hadm_id
)
SELECT
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohort;