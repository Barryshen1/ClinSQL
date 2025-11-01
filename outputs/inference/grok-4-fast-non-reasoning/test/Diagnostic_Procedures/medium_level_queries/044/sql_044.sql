WITH cohort_base AS (
  -- Base cohort with LOS calculation
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days,
    CASE 
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL 
    END AS los_category
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
    AND a.hospital_expire_flag = 0
    AND a.admission_type IN ('ELECTIVE', 'OBSERVATION')
),

cohort AS (
  -- Define ICU status after los_category is available
  SELECT 
    cb.*,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE icu.subject_id = cb.subject_id 
        AND icu.hadm_id = cb.hadm_id
    ) AS has_icu
  FROM 
    cohort_base cb
  WHERE 
    cb.los_category IS NOT NULL  -- Ensure only relevant LOS
),

-- Non-invasive diagnostics from ICU procedureevents
icu_procedures AS (
  SELECT DISTINCT
    pe.subject_id,
    pe.hadm_id,
    pe.itemid AS proc_code
  FROM 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  INNER JOIN 
    cohort c
    ON pe.subject_id = c.subject_id AND pe.hadm_id = c.hadm_id
  WHERE 
    di.category = 'Imaging'
    OR di.label LIKE '%ECG%' OR di.label LIKE '%EKG%' 
    OR di.label LIKE '%EEG%' OR di.label LIKE '%PFT%' OR di.label LIKE '%SPIROMETRY%'
    AND pe.starttime >= c.admittime
    AND pe.starttime <= c.dischtime
),

-- Non-invasive diagnostics from hospital procedures_icd
hosp_procedures AS (
  SELECT DISTINCT
    pi.subject_id,
    pi.hadm_id,
    pi.icd_code AS proc_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  INNER JOIN 
    cohort c
    ON pi.subject_id = c.subject_id AND pi.hadm_id = c.hadm_id
  WHERE 
    (dip.long_title LIKE '%X-RAY%' OR dip.long_title LIKE '%CT SCAN%' OR dip.long_title LIKE '%MRI%' 
     OR dip.long_title LIKE '%ULTRASOUND%' OR dip.long_title LIKE '%ELECTROCARDIOGRAM%' 
     OR dip.long_title LIKE '%ECG%' OR dip.long_title LIKE '%EEG%' 
     OR dip.long_title LIKE '%PULMONARY FUNCTION%' OR dip.long_title LIKE '%PFT%')
    AND pi.chartdate >= DATE(c.admittime)
    AND pi.chartdate <= DATE(c.dischtime)
),

-- Combine and count unique diagnostics per admission
diagnostic_counts AS (
  SELECT 
    c.hadm_id,
    c.los_category,
    c.has_icu,
    COUNT(DISTINCT ip.proc_code) + COUNT(DISTINCT hp.proc_code) AS non_invasive_count
  FROM 
    cohort c
  LEFT JOIN 
    icu_procedures ip
    ON c.subject_id = ip.subject_id AND c.hadm_id = ip.hadm_id
  LEFT JOIN 
    hosp_procedures hp
    ON c.subject_id = hp.subject_id AND c.hadm_id = hp.hadm_id
  GROUP BY 
    c.hadm_id, c.los_category, c.has_icu
)

SELECT 
  los_category,
  has_icu,
  COUNT(*) AS num_admissions,
  ROUND(AVG(non_invasive_count), 2) AS mean_non_invasive_per_admission
FROM 
  diagnostic_counts
WHERE 
  los_category IS NOT NULL
GROUP BY 
  los_category, has_icu
ORDER BY 
  los_category, has_icu;