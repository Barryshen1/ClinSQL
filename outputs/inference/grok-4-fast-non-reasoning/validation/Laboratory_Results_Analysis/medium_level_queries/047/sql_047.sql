WITH acs_admissions AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND (
      (d.icd_version = '10' AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%')) OR
      (d.icd_version = '9' AND d.icd_code LIKE '410%')
    )
),
initial_troponin AS (
  SELECT 
    aa.subject_id,
    aa.hadm_id,
    aa.admittime,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY aa.subject_id, aa.hadm_id 
      ORDER BY le.charttime ASC
    ) AS rn
  FROM acs_admissions aa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON aa.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE le.charttime > TIMESTAMP(aa.admittime)
    AND REGEXP_CONTAINS(li.label, r'(?i)troponin t')  -- Case-insensitive match for "Troponin T"
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0.01  -- Above 99th percentile (ng/mL)
),
first_troponins AS (
  SELECT 
    subject_id,
    hadm_id,
    valuenum AS initial_troponin
  FROM initial_troponin
  WHERE rn = 1
)
SELECT 
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  ROUND(AVG(initial_troponin), 4) AS mean_troponin,
  PERCENTILE_CONT(initial_troponin, 0.5) OVER () AS median_troponin,
  PERCENTILE_CONT(initial_troponin, 0.75) OVER () - PERCENTILE_CONT(initial_troponin, 0.25) OVER () AS iqr_troponin
FROM first_troponins;