WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        a.hadm_id = diag.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '435%')
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'G45%')
        )
    )
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 64 AND 74
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

icu_flag AS (
  SELECT 
    c.*,
    CASE WHEN i.hadm_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_use
  FROM cohort c
  LEFT JOIN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i ON c.hadm_id = i.hadm_id
),

procedures AS (
  SELECT 
    hadm_id,
    COUNT(*) AS num_procedures
  FROM (
    SELECT proc.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
      ON proc.icd_code = dip.icd_code AND proc.icd_version = dip.icd_version
    WHERE 
      LOWER(dip.long_title) LIKE '%ultrasound%'
      OR LOWER(dip.long_title) LIKE '%echocardiogram%'
      OR LOWER(dip.long_title) LIKE '%echo%'
      OR LOWER(dip.long_title) LIKE '%doppler%'
      OR LOWER(dip.long_title) LIKE '%carotid%'

    UNION ALL

    SELECT hcp.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcp
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh 
      ON hcp.hcpcs_cd = dh.code
    WHERE 
      LOWER(dh.long_description) LIKE '%ultrasound%'
      OR LOWER(dh.long_description) LIKE '%echocardiogram%'
      OR LOWER(dh.long_description) LIKE '%echo%'
      OR LOWER(dh.long_description) LIKE '%doppler%'
      OR LOWER(dh.long_description) LIKE '%carotid%'
  ) 
  GROUP BY hadm_id
)

SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_category,
  icu_use,
  AVG(COALESCE(p.num_procedures, 0)) AS mean_procedures_per_admission
FROM icu_flag c
LEFT JOIN procedures p 
  ON c.hadm_id = p.hadm_id
GROUP BY los_category, icu_use
ORDER BY los_category, icu_use;