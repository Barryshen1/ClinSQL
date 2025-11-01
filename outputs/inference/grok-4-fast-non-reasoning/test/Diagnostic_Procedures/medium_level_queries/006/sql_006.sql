WITH base_cohort AS (
  -- Base admissions with demographics and LOS
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.hospital_expire_flag = 0  -- Optional: exclude expired if needed; remove if include all
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 1 AND 8
),

sepsis_cohort AS (
  -- Filter for primary sepsis dx (no shock)
  SELECT 
    bc.*
  FROM 
    base_cohort bc
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON bc.subject_id = d.subject_id 
    AND CAST(bc.hadm_id AS STRING) = d.hadm_id
  WHERE 
    d.seq_num = 1
    AND d.icd_version = '10'
    AND (
      d.icd_code = 'R65.20' OR 
      d.icd_code LIKE 'A40.%' OR 
      d.icd_code LIKE 'A41.%'
    )
    AND d.icd_code NOT LIKE 'R65.21%'  -- Exclude severe sepsis with shock
),

icu_flag AS (
  -- Add ICU stratification
  SELECT 
    sc.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.transfers` t
        WHERE t.subject_id = sc.subject_id 
          AND CAST(sc.hadm_id AS STRING) = t.hadm_id
          AND t.careunit LIKE '%ICU%'
      ) THEN 'ICU' 
      ELSE 'No ICU' 
    END AS icu_stratum
  FROM 
    sepsis_cohort sc
),

ultrasound_counts AS (
  -- Count ultrasounds per admission
  SELECT 
    uf.subject_id,
    uf.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS ultrasound_count  -- Distinct codes per adm; or COUNT(*) for events
  FROM 
    icu_flag uf
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  ON uf.subject_id = pr.subject_id 
    AND CAST(uf.hadm_id AS STRING) = pr.hadm_id
  WHERE 
    pr.icd_version = '10'
    AND pr.icd_code LIKE 'BW[4-9]%'
  GROUP BY 
    uf.subject_id, uf.hadm_id
),

final_cohort AS (
  -- Combine with ultrasound counts (0 if none)
  SELECT 
    uf.subject_id,
    uf.hadm_id,
    CASE 
      WHEN uf.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      ELSE '5-8 days'
    END AS los_group,
    uf.icu_stratum,
    COALESCE(uc.ultrasound_count, 0) AS ultrasound_count
  FROM 
    icu_flag uf
  LEFT JOIN 
    ultrasound_counts uc
  ON uf.subject_id = uc.subject_id AND uf.hadm_id = uc.hadm_id
)

-- Aggregate: counts and means
SELECT 
  los_group,
  icu_stratum,
  COUNT(DISTINCT hadm_id) AS patient_counts,
  ROUND(AVG(ultrasound_count), 2) AS mean_ultrasounds_per_admission
FROM 
  final_cohort
GROUP BY 
  los_group, icu_stratum
ORDER BY 
  los_group, icu_stratum;