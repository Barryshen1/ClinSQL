WITH filtered_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime,
    pat.anchor_age,
    pat.anchor_year,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pat.gender = 'F'
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('411.1', '411.81') OR diag.icd_code LIKE '410%')
      OR
      (diag.icd_version = 10 AND diag.icd_code = 'I20.0' 
        OR diag.icd_code LIKE 'I21%' 
        OR diag.icd_code LIKE 'I22%' 
        OR diag.icd_code IN ('I24.0', 'I24.1', 'I24.8', 'I24.9'))
    )
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 68 AND 78
),
first_troponin AS (
  SELECT 
    lab.hadm_id,
    lab.valuenum AS initial_troponin,
    ROW_NUMBER() OVER (PARTITION BY lab.hadm_id ORDER BY lab.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
  INNER JOIN filtered_admissions fa
    ON lab.hadm_id = fa.hadm_id
  WHERE 
    lab.itemid = 50911  -- Troponin I
    AND lab.valuenum IS NOT NULL
),
valid_troponin_admissions AS (
  SELECT 
    ft.hadm_id,
    ft.initial_troponin
  FROM first_troponin ft
  WHERE 
    ft.rn = 1 
    AND ft.initial_troponin > 0.04
)
SELECT 
  COUNT(DISTINCT fa.subject_id) AS patient_count,
  COUNT(DISTINCT fa.hadm_id) AS admission_count,
  AVG(vt.initial_troponin) AS mean_initial_troponin,
  STDDEV(vt.initial_troponin) AS std_initial_troponin,
  MIN(vt.initial_troponin) AS min_initial_troponin,
  MAX(vt.initial_troponin) AS max_initial_troponin
FROM filtered_admissions fa
INNER JOIN valid_troponin_admissions vt
  ON fa.hadm_id = vt.hadm_id;