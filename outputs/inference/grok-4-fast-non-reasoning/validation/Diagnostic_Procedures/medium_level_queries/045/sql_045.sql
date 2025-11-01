WITH cohort AS (
  -- Base cohort: females 78-88 with DVT admission
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN 'Short (1-4 days)'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 8 THEN 'Long (5-8 days)'
      ELSE NULL 
    END AS los_group,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
        WHERE icu.subject_id = a.subject_id 
          AND CAST(icu.hadm_id AS STRING) = a.hadm_id
      ) THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_group
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND (
      (d.icd_version = '10' AND d.icd_code LIKE 'I82%') OR 
      (d.icd_version = '9' AND d.icd_code LIKE '453%')
    )
    AND d.seq_num = 1  -- Primary diagnosis
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8  -- Relevant LOS only
),

diagnostics AS (
  -- Count noninvasive diagnostics (D-dimer labs) per admission
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.los_group,
    c.icu_group,
    COUNT(DISTINCT le.labevent_id) AS num_diagnostics
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON c.subject_id = le.subject_id 
    AND c.hadm_id = le.hadm_id
    AND le.itemid IN (225169, 225170)  -- D-dimer itemids (ng/mL, ug/mL FEU)
    AND le.charttime >= c.admittime 
    AND le.charttime <= c.dischtime
    AND le.valuenum IS NOT NULL  -- Valid numeric result
  GROUP BY c.subject_id, c.hadm_id, c.los_group, c.icu_group
)

-- Aggregate: counts and mean diagnostics per admission
SELECT 
  los_group,
  icu_group,
  COUNT(DISTINCT hadm_id) AS admission_count,
  SUM(num_diagnostics) AS total_diagnostics,
  ROUND(AVG(num_diagnostics), 2) AS mean_diagnostics_per_admission
FROM diagnostics
GROUP BY los_group, icu_group
ORDER BY los_group, icu_group;