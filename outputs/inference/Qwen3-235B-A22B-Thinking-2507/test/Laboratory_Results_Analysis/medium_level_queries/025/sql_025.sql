WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 58 AND 68
),
chest_pain_ami AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '7865%') OR
    (icd_version = 10 AND icd_code LIKE 'R07.%') OR
    (icd_version = 9 AND icd_code LIKE '410%') OR
    (icd_version = 10 AND icd_code LIKE 'I21.%')
),
troponin_t AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY le.hadm_id 
      ORDER BY le.charttime, le.labevent_id
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE 
    dli.label LIKE '%Troponin T%'
    AND le.valuenum IS NOT NULL
    AND TRIM(LOWER(le.valueuom)) = 'ng/ml'
),
first_troponin AS (
  SELECT 
    hadm_id,
    valuenum AS first_trop
  FROM troponin_t
  WHERE rn = 1
    AND valuenum > 0.01
)
SELECT 
  AVG(first_trop) AS mean_trop,
  STDDEV(first_trop) AS std_trop,
  MIN(first_trop) AS min_trop,
  MAX(first_trop) AS max_trop
FROM first_troponin ft
INNER JOIN chest_pain_ami cpa 
  ON ft.hadm_id = cpa.hadm_id
INNER JOIN patient_admissions pa 
  ON ft.hadm_id = pa.hadm_id;