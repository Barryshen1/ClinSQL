WITH patients_filtered AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.gender = 'F'
),
admissions_with_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_filtered p ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
),
hf_diagnoses AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.age_at_admission
  FROM admissions_with_age a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE 
    (d.icd_code LIKE 'I50%' AND d.icd_version = 10)
    OR LOWER(d.long_title) LIKE '%heart failure%'
),
first_hf_admission AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM hf_diagnoses
  WHERE age_at_admission BETWEEN 38 AND 48
),
first_admissions_only AS (
  SELECT subject_id, hadm_id, dischtime
  FROM first_hf_admission
  WHERE rn = 1
),
readmissions AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.dischtime,
    a.admittime AS readmit_admittime,
    ROW_NUMBER() OVER (PARTITION BY f.subject_id ORDER BY a.admittime) AS readmit_rank
  FROM first_admissions_only f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON f.subject_id = a.subject_id
    AND a.admittime > f.dischtime
    AND a.admittime <= DATETIME_ADD(f.dischtime, INTERVAL 30 DAY)
)
SELECT
  AVG(CASE WHEN r.subject_id IS NOT NULL THEN 1.0 ELSE 0.0 END) AS thirty_day_readmission_rate
FROM first_admissions_only f
LEFT JOIN (
  SELECT DISTINCT subject_id
  FROM readmissions
  WHERE readmit_rank = 1
) r ON f.subject_id = r.subject_id;