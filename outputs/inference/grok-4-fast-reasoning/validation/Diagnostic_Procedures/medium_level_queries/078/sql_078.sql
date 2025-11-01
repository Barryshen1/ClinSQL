WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 88 AND 98
    AND a.admittime < a.dischtime
),
tia_admissions AS (
  SELECT DISTINCT 
    ea.hadm_id
  FROM eligible_admissions ea
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ea.hadm_id = di.hadm_id
  WHERE ((di.icd_version = 10 AND di.icd_code = 'G45.9')
     OR (di.icd_version = 9 AND di.icd_code = '435.9'))
),
admissions_with_los AS (
  SELECT 
    ta.hadm_id,
    ea.los_days,
    CASE 
      WHEN ea.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN ea.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group
  FROM tia_admissions ta
  INNER JOIN eligible_admissions ea 
    ON ta.hadm_id = ea.hadm_id
  WHERE ea.los_days BETWEEN 1 AND 7
),
admissions_with_icu AS (
  SELECT 
    awl.hadm_id,
    awl.los_days,
    awl.los_group,
    MAX(CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS has_icu
  FROM admissions_with_los awl
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON awl.hadm_id = i.hadm_id
  GROUP BY awl.hadm_id, awl.los_days, awl.los_group
),
imaging_counts AS (
  SELECT 
    awi.hadm_id,
    awi.los_group,
    awi.has_icu,
    COUNT(CASE 
      WHEN (LOWER(dp.long_title) LIKE '%ct%'
         OR LOWER(dp.long_title) LIKE '%mri%'
         OR LOWER(dp.long_title) LIKE '%computed tomography%'
         OR LOWER(dp.long_title) LIKE '%magnetic resonance imaging%')
      THEN 1 
    END) AS num_studies
  FROM admissions_with_icu awi
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON awi.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON proc.icd_code = dp.icd_code 
    AND proc.icd_version = dp.icd_version
  GROUP BY awi.hadm_id, awi.los_group, awi.has_icu
)
SELECT 
  los_group,
  has_icu,
  APPROX_QUANTILES(num_studies, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(num_studies, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(num_studies, 4)[OFFSET(3)] AS q3
FROM imaging_counts
GROUP BY los_group, has_icu
ORDER BY los_group, has_icu;