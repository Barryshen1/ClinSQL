WITH filtered_patients AS (
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 58 AND 68
),
admissions_with_diagnosis AS (
  SELECT DISTINCT a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN filtered_patients fp ON a.subject_id = fp.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON a.hadm_id = di.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE LOWER(did.long_title) LIKE LOWER('%chest pain%')
     OR LOWER(did.long_title) LIKE LOWER('%acute myocardial infarction%')
     OR LOWER(did.long_title) LIKE LOWER('%ami%')
),
troponin_t_first AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
  INNER JOIN admissions_with_diagnosis ad ON le.hadm_id = ad.hadm_id
  WHERE dl.label = 'Troponin T'
    AND le.valuenum > 0.01
    AND le.valuenum IS NOT NULL
)
SELECT 
  AVG(valuenum) AS mean_troponin_t,
  STDDEV(valuenum) AS stddev_troponin_t,
  MIN(valuenum) AS min_troponin_t,
  MAX(valuenum) AS max_troponin_t
FROM troponin_t_first
WHERE rn = 1;