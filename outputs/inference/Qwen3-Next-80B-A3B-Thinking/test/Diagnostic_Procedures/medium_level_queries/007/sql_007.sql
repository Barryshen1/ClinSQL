WITH female_50_60 AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 50 AND 60
),

acs_admissions AS (
  SELECT 
    f.hadm_id,
    d.seq_num
  FROM female_50_60 f
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON f.hadm_id = d.hadm_id
  WHERE d.icd_code IN ('I20.0', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4')
),

diagnosis_type AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN MAX(CASE WHEN seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type
  FROM acs_admissions
  GROUP BY hadm_id
),

procedure_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
),

los_categories AS (
  SELECT 
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL
    END AS los_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.hadm_id IN (SELECT hadm_id FROM diagnosis_type)
)

SELECT 
  los.los_category,
  dt.diagnosis_type,
  PERCENTILE_CONT(pc.procedure_count, 0.25) AS p25,
  PERCENTILE_CONT(pc.procedure_count, 0.5) AS p50,
  PERCENTILE_CONT(pc.procedure_count, 0.75) AS p75
FROM los_categories los
JOIN diagnosis_type dt ON los.hadm_id = dt.hadm_id
JOIN procedure_counts pc ON los.hadm_id = pc.hadm_id
GROUP BY los.los_category, dt.diagnosis_type;