WITH base_admissions AS (
  SELECT 
    a.hadm_id,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) BETWEEN 50 AND 60
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '435%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'G45%')
        )
    )
),
imaging_procedures AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE 
    LOWER(d.long_description) LIKE '%computed tomography%'
    OR LOWER(d.long_description) LIKE '%magnetic resonance imaging%'
  GROUP BY h.hadm_id
),
admission_metrics AS (
  SELECT 
    b.hadm_id,
    b.los_days,
    COALESCE(i.procedure_count, 0) AS procedure_count
  FROM base_admissions b
  LEFT JOIN imaging_procedures i
    ON b.hadm_id = i.hadm_id
  WHERE b.los_days BETWEEN 1 AND 7
)
SELECT
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  COUNT(*) AS count_admissions,
  AVG(procedure_count) AS mean_procedures
FROM admission_metrics
GROUP BY los_group
ORDER BY 
  CASE los_group
    WHEN '1-3 days' THEN 1
    WHEN '4-7 days' THEN 2
  END;