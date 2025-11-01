WITH patients_filtered AS (
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 83 AND 93
),
troponin_t AS (
  SELECT le.subject_id, le.valuenum, ROW_NUMBER() OVER (PARTITION BY le.subject_id ORDER BY le.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  WHERE dli.label LIKE '%Troponin T%' AND le.subject_id IN (SELECT subject_id FROM patients_filtered)
),
ami_patients AS (
  SELECT DISTINCT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Acute myocardial infarction%' AND di.subject_id IN (SELECT subject_id FROM patients_filtered)
),
troponin_percentile AS (
  SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(99)] as percentile_99
  FROM troponin_t
  WHERE rn = 1
),
filtered_patients AS (
  SELECT tt.subject_id, p.anchor_age, icu.los, tt.valuenum
  FROM troponin_t tt
  JOIN patients_filtered p ON tt.subject_id = p.subject_id
  JOIN ami_patients ap ON tt.subject_id = ap.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON tt.subject_id = icu.subject_id
  WHERE tt.rn = 1 AND tt.valuenum > (SELECT percentile_99 FROM troponin_percentile)
)
SELECT 
  COUNT(*) as N,
  AVG(anchor_age) as mean_age,
  AVG(los) as mean_los,
  AVG(valuenum) as mean_troponin,
  MIN(valuenum) as min_troponin,
  MAX(valuenum) as max_troponin
FROM filtered_patients;