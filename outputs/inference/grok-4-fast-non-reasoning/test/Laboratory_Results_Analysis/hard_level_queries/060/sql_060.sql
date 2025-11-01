WITH first_admissions AS (
  -- First admission per patient (females 52-62)
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admittime >= '2008-01-01'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),

has_cardiac_arrest AS (
  -- Subquery to flag admissions with principal cardiac arrest diagnosis (ICD-10)
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 'ICD-10-CM'
    AND icd_code IN ('I462', 'I468', 'I469')
    AND seq_num = '1'  -- Principal diagnosis as string
),

cohort AS (
  -- Define cohorts: cardiac arrest vs general inpatients
  SELECT 
    fa.*,
    CASE 
      WHEN hca.hadm_id IS NOT NULL THEN 1 
      ELSE 0 
    END AS cardiac_arrest
  FROM first_admissions fa
  LEFT JOIN has_cardiac_arrest hca
    ON fa.hadm_id = hca.hadm_id
),

critical_labs AS (
  -- Critical lab events in first 48h
  SELECT 
    c.subject_id,
    c.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper,
    l.flag,
    CASE 
      WHEN l.valuenum IS NOT NULL 
        AND ((l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower) 
             OR (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper))
        OR l.flag = 'abnormal' 
      THEN 1 ELSE 0 
    END AS is_critical
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli 
    ON l.itemid = dli.itemid
  WHERE l.charttime >= c.admittime
    AND l.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
    AND dli.category IN ('Routine', 'Blood Gas', 'Chemistry', 'Hematology', 'Urine')
    AND dli.loinc_code IS NOT NULL
),

patient_instability AS (
  -- Per-patient instability score (count of critical events in 48h)
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.cardiac_arrest,
    COUNTIF(cl.is_critical = 1) AS instability_score,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    CASE WHEN c.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality
  FROM cohort c
  LEFT JOIN critical_labs cl 
    ON c.subject_id = cl.subject_id AND c.hadm_id = cl.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.cardiac_arrest, c.dischtime, c.admittime, c.hospital_expire_flag
),

admission_critical AS (
  -- Critical labs in first 24h for admission comparison (unique itemids)
  SELECT 
    c.subject_id,
    c.cardiac_arrest,
    COUNT(DISTINCT cl.itemid) AS critical_items_at_admission
  FROM cohort c
  INNER JOIN critical_labs cl 
    ON c.subject_id = cl.subject_id AND c.hadm_id = cl.hadm_id
  WHERE cl.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
    AND cl.is_critical = 1
  GROUP BY c.subject_id, c.cardiac_arrest
),

instability_iqr AS (
  -- Compute IQR for instability score by cohort
  SELECT 
    cardiac_arrest,
    PERCENTILE_CONT(0.25, instability_score) AS q1_instability,
    PERCENTILE_CONT(0.5, instability_score) AS median_instability
  FROM patient_instability
  GROUP BY cardiac_arrest
),

cohort_stats AS (
  -- Aggregated stats per cohort
  SELECT 
    pi.cardiac_arrest,
    i.q1_instability,
    i.median_instability,
    AVG(COALESCE(ac.critical_items_at_admission, 0)) AS avg_critical_items_at_admission,
    PERCENTILE_CONT(0.5, pi.los_days) AS median_los_days,
    AVG(pi.los_days) AS avg_los_days,
    AVG(pi.mortality) * 100 AS mortality_pct
  FROM patient_instability pi
  INNER JOIN instability_iqr i 
    ON pi.cardiac_arrest = i.cardiac_arrest
  LEFT JOIN admission_critical ac 
    ON pi.subject_id = ac.subject_id AND pi.cardiac_arrest = ac.cardiac_arrest
  GROUP BY pi.cardiac_arrest, i.q1_instability, i.median_instability
)

-- Main results
SELECT 
  cardiac_arrest,
  q1_instability,
  median_instability,
  avg_critical_items_at_admission,
  median_los_days,
  avg_los_days,
  mortality_pct
FROM cohort_stats
ORDER BY cardiac_arrest DESC;