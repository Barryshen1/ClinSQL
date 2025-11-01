WITH base_admissions AS (
  SELECT 
    adm.hadm_id,
    adm.subject_id,
    adm.admittime,
    adm.dischtime,
    adm.edregtime,
    -- Compute start_time for lab events: COALESCE(edregtime, admittime)
    COALESCE(adm.edregtime, adm.admittime) AS start_time,
    -- Compute age at admission
    pat.anchor_age - (pat.anchor_year - EXTRACT(YEAR FROM adm.admittime)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pat.gender = 'F'
    AND (pat.anchor_age - (pat.anchor_year - EXTRACT(YEAR FROM adm.admittime))) BETWEEN 68 AND 78
    AND diag.seq_num = 1  -- primary diagnosis
    AND (
      (diag.icd_version = 9 AND (diag.icd_code LIKE '410%' OR diag.icd_code = '4111'))
      OR
      (diag.icd_version = 10 AND (diag.icd_code = 'I200' OR diag.icd_code LIKE 'I21%'))
    )
),
troponin_first AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  INNER JOIN base_admissions ba
    ON le.hadm_id = ba.hadm_id
  WHERE 
    dli.label = 'Troponin I'
    AND le.charttime >= ba.start_time
    AND le.charttime <= ba.dischtime
    AND le.valuenum IS NOT NULL
)
SELECT 
  COUNT(DISTINCT ba.subject_id) AS patient_count,
  COUNT(DISTINCT ba.hadm_id) AS admission_count,
  AVG(tf.valuenum) AS mean_troponin,
  STDDEV(tf.valuenum) AS std_troponin,
  MIN(tf.valuenum) AS min_troponin,
  MAX(tf.valuenum) AS max_troponin
FROM base_admissions ba
INNER JOIN troponin_first tf
  ON ba.hadm_id = tf.hadm_id
WHERE 
  tf.rn = 1
  AND tf.valuenum > 0.04;