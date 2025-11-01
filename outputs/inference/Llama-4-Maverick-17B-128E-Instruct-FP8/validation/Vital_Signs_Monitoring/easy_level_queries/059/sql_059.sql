WITH 
-- Filter patients
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 77 AND 87
),

-- Get admissions for filtered patients
admissions_filtered AS (
  SELECT a.hadm_id, a.subject_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN filtered_patients p ON a.subject_id = p.subject_id
),

-- Get first SpO2 measurement for each admission
first_spo2 AS (
  SELECT af.hadm_id, ce.valuenum, ROW_NUMBER() OVER (PARTITION BY af.hadm_id ORDER BY ce.charttime) as rn
  FROM admissions_filtered af
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON af.hadm_id = ce.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.itemid = 220277 AND ce.valuenum IS NOT NULL
)

-- Calculate standard deviation of first SpO2
SELECT STDDEV(valuenum) as std_dev_first_spo2
FROM first_spo2
WHERE rn = 1;