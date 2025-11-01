WITH patients AS (
  SELECT subject_id, gender, anchor_age, anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
),
admissions AS (
  SELECT subject_id, hadm_id, admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
diagnoses AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND (icd_code LIKE '433%' OR icd_code LIKE '434%' OR icd_code = '436'))
    OR
    (icd_version = 10 AND icd_code LIKE 'I63%')
  )
),
qualifying_adms AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm
  FROM admissions a
  INNER JOIN patients p ON a.subject_id = p.subject_id
  INNER JOIN diagnoses d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) = 82
),
glucose_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%glucose%'
    AND category = 'Chemistry'
    AND fluid = 'Blood'
),
glucose_labs AS (
  SELECT 
    le.subject_id, 
    le.hadm_id, 
    le.charttime, 
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN glucose_items gi ON le.itemid = gi.itemid
  INNER JOIN qualifying_adms qa ON le.subject_id = qa.subject_id AND le.hadm_id = qa.hadm_id
  WHERE le.valuenum IS NOT NULL
    AND le.valueuom = 'mg/dL'
    AND le.charttime >= qa.admittime
),
first_glucose AS (
  SELECT subject_id, hadm_id, valuenum AS admission_glucose
  FROM (
    SELECT 
      subject_id, 
      hadm_id, 
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
    FROM glucose_labs
  )
  WHERE rn = 1
)
SELECT APPROX_QUANTILES(admission_glucose, 4)[OFFSET(3)] AS p75_admission_glucose_mg_dl
FROM first_glucose;