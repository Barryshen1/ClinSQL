WITH acs_adms AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.seq_num = 1
    AND (
      (di.icd_version = '9' AND (di.icd_code LIKE '410.%' OR di.icd_code = '411.1'))
      OR
      (di.icd_version = '10' AND (di.icd_code LIKE 'I21.%' OR di.icd_code = 'I20.0'))
    )
),
female_age_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 68 AND 78
),
first_troponin AS (
  SELECT hadm_id, valuenum AS initial_troponin
  FROM (
    SELECT 
      hadm_id, 
      charttime, 
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC, labevent_id ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE itemid = 33564
      AND valueuom = 'ng/mL'
      AND valuenum IS NOT NULL
  )
  WHERE rn = 1
)
SELECT 
  COUNT(DISTINCT fap.subject_id) AS patient_count,
  COUNT(DISTINCT aa.hadm_id) AS admission_count,
  AVG(ft.initial_troponin) AS mean_troponin,
  STDDEV(ft.initial_troponin) AS sd_troponin,
  MIN(ft.initial_troponin) AS min_troponin,
  MAX(ft.initial_troponin) AS max_troponin
FROM acs_adms aa
INNER JOIN female_age_patients fap ON aa.subject_id = fap.subject_id
INNER JOIN first_troponin ft ON aa.hadm_id = ft.hadm_id
WHERE ft.initial_troponin > 0.04;