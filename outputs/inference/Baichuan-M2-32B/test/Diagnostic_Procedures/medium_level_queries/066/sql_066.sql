WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.dischtime IS NOT NULL
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 88 AND 98
),
asthma_admissions AS (
  SELECT DISTINCT e.hadm_id, e.los_days
  FROM eligible_admissions e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON e.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.long_title LIKE '%asthma%'
),
procedure_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
),
admission_procedures AS (
  SELECT 
    a.hadm_id,
    a.los_days,
    COALESCE(p.procedure_count, 0) AS procedure_count
  FROM asthma_admissions a
  LEFT JOIN procedure_counts p 
    ON a.hadm_id = p.hadm_id
),
los_groups AS (
  SELECT 
    procedure_count,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL 
    END AS los_group
  FROM admission_procedures
  WHERE los_days BETWEEN 1 AND 7
)
SELECT 
  los_group,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS p75
FROM los_groups
GROUP BY los_group;