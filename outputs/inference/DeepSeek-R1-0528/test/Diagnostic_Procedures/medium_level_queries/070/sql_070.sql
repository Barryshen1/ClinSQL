WITH hf_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    CAST(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS INT) AS age_admit,
    -- Calculate LOS in days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '428%') 
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
        )
    )
),
filtered_admissions AS (
  SELECT *
  FROM hf_admissions
  WHERE age_admit BETWEEN 59 AND 69
),
with_icu_flag AS (
  SELECT 
    fa.*,
    CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS icu_used
  FROM filtered_admissions fa
  LEFT JOIN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i ON fa.hadm_id = i.hadm_id
),
proc_counts AS (
  SELECT 
    proc.hadm_id,
    COUNT(*) AS proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON proc.icd_code = dip.icd_code 
    AND proc.icd_version = dip.icd_version
  WHERE 
    LOWER(dip.long_title) LIKE '%radiograph%' 
    OR LOWER(dip.long_title) LIKE '%x-ray%' 
    OR LOWER(dip.long_title) LIKE '%ct%' 
    OR LOWER(dip.long_title) LIKE '%computed tomography%'
  GROUP BY proc.hadm_id
),
final_data AS (
  SELECT 
    wif.hadm_id,
    wif.los_days,
    wif.icu_used,
    COALESCE(pc.proc_count, 0) AS proc_count
  FROM with_icu_flag wif
  LEFT JOIN proc_counts pc
    ON wif.hadm_id = pc.hadm_id
  WHERE wif.los_days BETWEEN 1 AND 8  -- Only include 1-8 day stays
)
SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
    WHEN los_days BETWEEN 5 AND 8 THEN '5-8'
  END AS los_group,
  icu_used,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(3)] AS p75
FROM final_data
GROUP BY los_group, icu_used
ORDER BY los_group, icu_used;