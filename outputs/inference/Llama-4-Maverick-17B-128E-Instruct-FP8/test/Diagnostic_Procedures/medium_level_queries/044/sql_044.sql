WITH 
lower_gi_bleed_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10 AND lower(long_title) LIKE '%lower gastrointestinal bleeding%'
),
lower_gi_bleed_patients AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN lower_gi_bleed_icd lgib ON di.icd_code = lgib.icd_code
  WHERE di.icd_version = 10
),
cohort AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, 
         CASE WHEN ic.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_status,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic ON a.hadm_id = ic.hadm_id
  JOIN lower_gi_bleed_patients lgibp ON a.hadm_id = lgibp.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 62 AND 72
),
non_invasive_diagnostics AS (
  SELECT hadm_id, COUNT(*) AS num_diagnostics
  FROM (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE LOWER(short_description) LIKE '%imaging%' OR LOWER(short_description) LIKE '%ct scan%' OR LOWER(short_description) LIKE '%mri%'
    UNION ALL
    SELECT ce.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
    WHERE LOWER(di.label) LIKE '%ecg%' OR LOWER(di.label) LIKE '%eeg%' OR LOWER(di.label) LIKE '%pft%'
  )
  GROUP BY hadm_id
)
SELECT 
  CASE WHEN c.los BETWEEN 1 AND 3 THEN '1-3 days' 
       WHEN c.los BETWEEN 4 AND 7 THEN '4-7 days' 
       ELSE 'More than 7 days' END AS los_category,
  c.icu_status,
  AVG(nid.num_diagnostics) AS mean_num_diagnostics
FROM cohort c
LEFT JOIN non_invasive_diagnostics nid ON c.hadm_id = nid.hadm_id
WHERE c.los BETWEEN 1 AND 7
GROUP BY los_category, c.icu_status
ORDER BY los_category, c.icu_status;