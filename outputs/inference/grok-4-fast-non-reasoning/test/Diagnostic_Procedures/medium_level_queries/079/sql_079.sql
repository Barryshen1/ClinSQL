WITH cohort AS (
  -- Base cohort: females aged 71-81 with admissions
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND a.admittime IS NOT NULL 
    AND a.dischtime IS NOT NULL
),

lgib_admissions AS (
  -- Admissions with LGIB diagnosis (primary or secondary)
  SELECT 
    c.*,
    d.seq_num,
    CASE 
      WHEN d.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type,
    CASE 
      WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN c.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON 
    c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
  ON 
    d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE 
    c.los_days BETWEEN 1 AND 7
    AND (
      -- ICD-9 and ICD-10 codes for lower GI bleed (examples)
      d.icd_code IN ('562.12', '562.13', '569.3', '537.82',  -- ICD-9
                     'K57.31', 'K57.33', 'K57.41', 'K57.43', 'K92.2', 'K77.5')  -- ICD-10
      OR icd.long_title LIKE '%lower gastrointestinal hemorrhage%'
      OR icd.long_title LIKE '%diverticular bleed%'
      OR icd.long_title LIKE '%angiodysplasia%'
    )
    AND c.los_days BETWEEN 1 AND 7  -- Ensures 1-7 days (replaces los_group filter)
),

imaging_counts AS (
  -- Count distinct imaging events per admission (proxy for CT/radiography)
  SELECT 
    la.hadm_id,
    COUNT(DISTINCT ce.charttime) AS imaging_count
  FROM 
    lgib_admissions la
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    la.hadm_id = ce.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON 
    ce.itemid = di.itemid
  WHERE 
    di.itemid IN (220739, 228073, 220452)  -- CT head, chest, abdomen/pelvis
    AND ce.charttime IS NOT NULL
  GROUP BY 
    la.hadm_id
)

-- Aggregate means by group
SELECT 
  la.diagnosis_type,
  la.los_group,
  COUNT(DISTINCT la.hadm_id) AS num_admissions,
  COALESCE(AVG(ic.imaging_count), 0) AS mean_imaging_per_admission
FROM 
  lgib_admissions la
LEFT JOIN 
  imaging_counts ic
ON 
  la.hadm_id = ic.hadm_id
GROUP BY 
  la.diagnosis_type, 
  la.los_group
ORDER BY 
  diagnosis_type, 
  CASE los_group 
    WHEN '1-3 days' THEN 1 
    WHEN '4-7 days' THEN 2 
  END;