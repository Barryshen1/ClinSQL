WITH stroke_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code >= '430' AND icd_code < '439')
    OR
    (icd_version = 10 AND icd_code >= 'I60' AND icd_code < 'I70')
),
eligible_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_seq
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND a.hadm_id IN (SELECT hadm_id FROM stroke_admissions)
),
first_eligible_admission AS (
  SELECT 
    subject_id,
    hadm_id
  FROM eligible_patients
  WHERE 
    age_at_admission BETWEEN 46 AND 56
    AND admission_seq = 1
),
icu_los AS (
  SELECT 
    fea.subject_id,
    fea.hadm_id,
    SUM(i.los) AS total_icu_los_days
  FROM first_eligible_admission fea
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON fea.hadm_id = i.hadm_id
  GROUP BY fea.subject_id, fea.hadm_id
),
percentiles AS (
  SELECT 
    PERCENTILE_CONT(total_icu_los_days, 0.25) OVER () AS q1,
    PERCENTILE_CONT(total_icu_los_days, 0.75) OVER () AS q3
  FROM icu_los
  LIMIT 1
)
SELECT 
  q3 - q1 AS iqr
FROM percentiles;