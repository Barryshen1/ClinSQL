WITH 
-- Filter patients by age and gender
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 37 AND 47
),

-- Identify ICU stays for eligible patients
icu_stays AS (
  SELECT ie.stay_id, ie.hadm_id, ie.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN eligible_patients ep ON ie.subject_id = ep.subject_id
),

-- Identify stays with CPAP or BiPAP
ventilation_stays AS (
  SELECT DISTINCT pe.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN icu_stays icus ON pe.stay_id = icus.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE di.label IN ('CPAP', 'BiPAP')  -- Adjust based on actual labels or itemids
),

-- Get max diastolic blood pressure per stay
max_diastolic_bp AS (
  SELECT vs.stay_id, MAX(ce.valuenum) AS max_diastolic_bp
  FROM ventilation_stays vs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON vs.stay_id = ce.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.itemid = 220051  -- Adjust based on actual itemid for diastolic BP
  GROUP BY vs.stay_id
)

-- Calculate the 25th percentile of max diastolic BP
SELECT 
  APPROX_QUANTILES(max_diastolic_bp, 100)[OFFSET(25)] AS percentile_25th
FROM (
  SELECT mdb.max_diastolic_bp 
  FROM max_diastolic_bp mdb
);