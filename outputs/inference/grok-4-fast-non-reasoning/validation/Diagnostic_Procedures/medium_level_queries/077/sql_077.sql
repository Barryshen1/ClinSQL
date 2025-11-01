WITH patient_admissions AS (
  -- Base cohort: females aged 57-67 at admission, non-newborn admissions
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    -- Compute precise age at admission using DOB approximation
    DATE_DIFF(a.admittime, DATE(p.anchor_year, 1, 1) - INTERVAL (100 - p.anchor_age) YEAR, YEAR) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND DATE_DIFF(a.admittime, DATE(p.anchor_year, 1, 1) - INTERVAL (100 - p.anchor_age) YEAR, YEAR) BETWEEN 57 AND 67
    AND (p.dod > a.admittime OR p.dod IS NULL)  -- Exclude if died before/on admission
    AND a.admission_type != 'NEWBORN'
),
icu_flags AS (
  -- Flag admissions with any ICU stay using icustays
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.subject_id = pa.subject_id 
          AND i.hadm_id = pa.hadm_id
      ) THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_group
  FROM patient_admissions pa
),
ultrasound_counts AS (
  -- Count distinct ultrasounds per admission across procedureevents and hcpcsevents (deduplicated)
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    COUNT(DISTINCT ultrasound_event) AS ultrasound_count
  FROM patient_admissions pa
  LEFT JOIN (
    -- ICU procedureevents ultrasounds
    SELECT 
      pe.subject_id,
      pe.hadm_id,
      CONCAT('proc_', CAST(pe.itemid AS STRING)) AS ultrasound_event
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    WHERE pe.itemid IN (220037, 220218, 220219, 220467, 228139, 228161)
      AND pe.starttime >= pa.admittime
      AND pe.starttime <= pa.dischtime
    
    UNION DISTINCT
    
    -- Hospital billing ultrasounds
    SELECT 
      he.subject_id,
      he.hadm_id,
      CONCAT('bill_', he.hcpcs_cd) AS ultrasound_event
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
    WHERE he.hcpcs_cd IN ('93306', '93307', '93308', '93312', '93303', '76700', '76705', '76856', '93970', '93971')
      AND he.chartdate >= DATE(pa.admittime)
      AND he.chartdate <= DATE(pa.dischtime)
  ) us ON pa.subject_id = us.subject_id AND pa.hadm_id = us.hadm_id
  GROUP BY pa.subject_id, pa.hadm_id
)
-- Aggregate percentiles by LOS and ICU groups
SELECT 
  CASE 
    WHEN pa.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN pa.los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  if.icu_group,
  PERCENTILE_CONT(uc.ultrasound_count, 0.25) OVER (PARTITION BY CASE WHEN pa.los_days BETWEEN 1 AND 3 THEN '1-3 days' WHEN pa.los_days BETWEEN 4 AND 7 THEN '4-7 days' END, if.icu_group) AS p25,
  PERCENTILE_CONT(uc.ultrasound_count, 0.5) OVER (PARTITION BY CASE WHEN pa.los_days BETWEEN 1 AND 3 THEN '1-3 days' WHEN pa.los_days BETWEEN 4 AND 7 THEN '4-7 days' END, if.icu_group) AS p50,
  PERCENTILE_CONT(uc.ultrasound_count, 0.75) OVER (PARTITION BY CASE WHEN pa.los_days BETWEEN 1 AND 3 THEN '1-3 days' WHEN pa.los_days BETWEEN 4 AND 7 THEN '4-7 days' END, if.icu_group) AS p75,
  COUNT(*) OVER (PARTITION BY CASE WHEN pa.los_days BETWEEN 1 AND 3 THEN '1-3 days' WHEN pa.los_days BETWEEN 4 AND 7 THEN '4-7 days' END, if.icu_group) AS n_admissions
FROM patient_admissions pa
INNER JOIN icu_flags if ON pa.subject_id = if.subject_id AND pa.hadm_id = if.hadm_id
LEFT JOIN ultrasound_counts uc ON pa.subject_id = uc.subject_id AND pa.hadm_id = uc.hadm_id
WHERE pa.los_days BETWEEN 1 AND 7  -- Only specified LOS buckets
ORDER BY los_group, icu_group;