WITH
-- Define AKI ICD codes
aki_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN (
    '584', '5849', 'N17', 'N179',
    '584.5', '584.6', '584.7', '584.8', '584.9',
    'N17.0', 'N17.1', 'N17.2', 'N17.8', 'N17.9'
  )
),

-- Get female admissions aged 84-94 with AKI
female_aki_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN aki_icd_codes ak ON d.icd_code = ak.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND a.hadm_id IS NOT NULL
),

-- Calculate medication complexity score (count of distinct drugs per admission)
med_complexity AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT drug) AS complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE hadm_id IN (SELECT hadm_id FROM female_aki_admissions)
  GROUP BY hadm_id
),

-- Assign quintiles based on medication complexity
quintiles AS (
  SELECT
    hadm_id,
    complexity_score,
    NTILE(5) OVER (ORDER BY complexity_score) AS quintile
  FROM med_complexity
),

-- Calculate LOS (in days)
los AS (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS length_of_stay
  FROM female_aki_admissions
),

-- Identify 30-day readmissions
readmissions AS (
  SELECT
    a1.hadm_id AS original_hadm_id,
    a2.hadm_id AS readmission_hadm_id,
    TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) AS days_to_readmit
  FROM female_aki_admissions a1
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2 ON a1.subject_id = a2.subject_id
  WHERE a2.admittime > a1.dischtime
    AND TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) <= 30
),

-- Identify anticoagulant and opioid prescriptions
anticoagulants AS (
  SELECT
    hadm_id,
    drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%warfarin%'
     OR LOWER(drug) LIKE '%heparin%'
     OR LOWER(drug) LIKE '%enoxaparin%'
     OR LOWER(drug) LIKE '%apixaban%'
     OR LOWER(drug) LIKE '%rivaroxaban%'
     OR LOWER(drug) LIKE '%dabigatran%'
     OR LOWER(drug) LIKE '%fondaparinux%'
),

opioids AS (
  SELECT
    hadm_id,
    drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%morphine%'
     OR LOWER(drug) LIKE '%fentanyl%'
     OR LOWER(drug) LIKE '%oxycodone%'
     OR LOWER(drug) LIKE '%hydromorphone%'
     OR LOWER(drug) LIKE '%codeine%'
     OR LOWER(drug) LIKE '%hydrocodone%'
     OR LOWER(drug) LIKE '%tramadol%'
     OR LOWER(drug) LIKE '%meperidine%'
),

-- Count coadministrations
coadmin AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT o.drug) AS coadmin_count
  FROM anticoagulants a
  JOIN opioids o ON a.hadm_id = o.hadm_id
  GROUP BY a.hadm_id
)

-- Final aggregated results
SELECT
  q.quintile,
  COUNT(DISTINCT f.hadm_id) AS admission_count,
  AVG(l.length_of_stay) AS avg_los,
  SUM(CASE WHEN f.hospital_expire_flag = 1 THEN 1 ELSE 0 END) /
    COUNT(DISTINCT f.hadm_id) * 100 AS mortality_pct,
  SUM(CASE WHEN r.original_hadm_id IS NOT NULL THEN 1 ELSE 0 END) /
    COUNT(DISTINCT f.hadm_id) * 100 AS readmission_30day_pct,
  AVG(COALESCE(c.coadmin_count, 0)) AS avg_anticoag_opioid_coadmin
FROM quintiles q
JOIN female_aki_admissions f ON q.hadm_id = f.hadm_id
LEFT JOIN los l ON q.hadm_id = l.hadm_id
LEFT JOIN readmissions r ON q.hadm_id = r.original_hadm_id
LEFT JOIN coadmin c ON q.hadm_id = c.hadm_id
GROUP BY q.quintile
ORDER BY q.quintile;