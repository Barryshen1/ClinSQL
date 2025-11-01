WITH acs_patients AS (
  -- Identify ACS patients who are female and aged 50-60
  SELECT 
    p.subject_id,
    a.hadm_id,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 50 AND 60
    AND EXISTS (
      -- Check if patient has ACS diagnosis
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- ICD-9 codes for ACS
          (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '411%'))
          OR
          -- ICD-10 codes for ACS
          (d.icd_version = 10 AND (
            d.icd_code LIKE 'I20.0%' OR
            d.icd_code LIKE 'I21%' OR
            d.icd_code LIKE 'I22%' OR
            d.icd_code LIKE 'I24%'
          ))
        )
    )
),

procedure_counts AS (
  -- Count procedures per admission
  SELECT 
    ap.hadm_id,
    COUNT(*) AS procedure_count
  FROM acs_patients ap
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd p
    ON ap.hadm_id = p.hadm_id
  GROUP BY ap.hadm_id
),

los_groups AS (
  -- Calculate LOS and categorize
  SELECT 
    ap.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM acs_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON ap.hadm_id = a.hadm_id
  WHERE DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),

diagnosis_type AS (
  -- Determine if ACS is primary diagnosis
  SELECT 
    ap.hadm_id,
    MAX(CASE WHEN d.seq_num = 1 AND (
        (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '411%'))
        OR
        (d.icd_version = 10 AND (
          d.icd_code LIKE 'I20.0%' OR
          d.icd_code LIKE 'I21%' OR
          d.icd_code LIKE 'I22%' OR
          d.icd_code LIKE 'I24%'
        ))
      ) THEN 1 ELSE 0 END) AS is_primary
  FROM acs_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON ap.hadm_id = d.hadm_id
  GROUP BY ap.hadm_id
)

-- Final query to calculate percentiles
SELECT 
  lg.los_group,
  CASE WHEN dt.is_primary = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_position,
  APPROX_QUANTILES(pc.procedure_count, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(pc.procedure_count, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(pc.procedure_count, 100)[OFFSET(75)] AS p75
FROM procedure_counts pc
INNER JOIN los_groups lg
  ON pc.hadm_id = lg.hadm_id
INNER JOIN diagnosis_type dt
  ON pc.hadm_id = dt.hadm_id
GROUP BY lg.los_group, diagnosis_position
ORDER BY lg.los_group, diagnosis_position;