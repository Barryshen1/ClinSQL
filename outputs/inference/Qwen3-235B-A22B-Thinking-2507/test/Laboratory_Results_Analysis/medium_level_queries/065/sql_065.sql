WITH ami_admissions AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission,
    COALESCE(a.edregtime, a.admittime) AS admission_start,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND d.seq_num = 1  -- Primary diagnosis
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')  -- ICD-9 AMI codes
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))  -- ICD-10 AMI codes
    )
),
filtered_ami AS (
  SELECT *
  FROM ami_admissions
  WHERE age_at_admission BETWEEN 49 AND 59
),
first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (
      PARTITION BY l.hadm_id 
      ORDER BY l.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  INNER JOIN filtered_ami a
    ON l.hadm_id = a.hadm_id
  WHERE 
    d.label = 'Troponin T'  -- Standard MIMIC-IV label
    AND l.valueuom = 'ng/mL'  -- Enforce unit consistency
    AND l.valuenum IS NOT NULL  -- Exclude non-numeric values
    AND l.charttime >= a.admission_start
    AND l.charttime <= a.dischtime
)
SELECT
  APPROX_QUANTILES(troponin_value, 1000)[OFFSET(500)] AS median,
  APPROX_QUANTILES(troponin_value, 1000)[OFFSET(750)] - 
  APPROX_QUANTILES(troponin_value, 1000)[OFFSET(250)] AS iqr
FROM first_troponin
WHERE rn = 1 AND troponin_value > 0.04;  -- First value > 0.04 ng/mL;