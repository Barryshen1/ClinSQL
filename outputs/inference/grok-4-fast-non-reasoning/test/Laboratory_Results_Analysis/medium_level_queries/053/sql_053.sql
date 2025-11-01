WITH acs_patients AS (
  -- Filter female patients aged 68-78 with principal ACS diagnosis (ICD-10 I20/I21)
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 68 AND 78
    AND d.seq_num = 1  -- Principal diagnosis
    AND d.icd_version = '10'
    AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%')  -- I20/I21 for ACS (unstable angina/AMI)
),
first_troponin AS (
  -- Get first Troponin I per admission, filter >0.04 ng/mL
  SELECT 
    ap.subject_id,
    ap.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY ap.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM acs_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON li.category = 'Chemistry'  -- Troponin I is typically Chemistry
    AND (li.label LIKE '%TroponinI%' OR li.label LIKE '%TROPONIN I%')
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON ap.subject_id = l.subject_id
    AND ap.hadm_id = l.hadm_id
    AND l.itemid = li.itemid
    AND l.charttime >= ap.admittime
    AND l.charttime <= ap.dischtime  -- Within admission
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
    AND l.valuenum > 0.04
)
SELECT 
  COUNT(DISTINCT ft.subject_id) AS patient_count,
  COUNT(DISTINCT ft.hadm_id) AS admission_count,
  AVG(ft.valuenum) AS mean_troponin,
  STDDEV(ft.valuenum) AS sd_troponin,
  MIN(ft.valuenum) AS min_troponin,
  MAX(ft.valuenum) AS max_troponin
FROM first_troponin ft
WHERE ft.rn = 1;  -- Only the first measurement per admission;