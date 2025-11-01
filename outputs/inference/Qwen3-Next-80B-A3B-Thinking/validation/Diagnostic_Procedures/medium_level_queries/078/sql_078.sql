WITH tia_diagnoses AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%Transient Ischemic Attack%' OR long_title LIKE '%TIA%'
),
tia_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN tia_diagnoses t ON d.icd_code = t.icd_code AND d.icd_version = t.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 88 AND 98
),
los_icu AS (
  SELECT 
    ta.hadm_id,
    TIMESTAMP_DIFF(ta.dischtime, ta.admittime, DAY) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 'yes' ELSE 'no' END AS icu_use
  FROM tia_admissions ta
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ta.hadm_id = i.hadm_id
  WHERE TIMESTAMP_DIFF(ta.dischtime, ta.admittime, DAY) BETWEEN 1 AND 7
),
ct_mri_count AS (
  SELECT hadm_id, SUM(count_studies) AS count_studies
  FROM (
    SELECT c.hadm_id, COUNT(*) AS count_studies
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON c.itemid = di.itemid
    WHERE di.linksto = 'chartevents' AND (di.label LIKE '%CT%' OR di.label LIKE '%MRI%')
    GROUP BY c.hadm_id
    UNION ALL
    SELECT p.hadm_id, COUNT(*) AS count_studies
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON p.itemid = di.itemid
    WHERE di.linksto = 'procedureevents' AND (di.label LIKE '%CT%' OR di.label LIKE '%MRI%')
    GROUP BY p.hadm_id
  ) combined
  GROUP BY hadm_id
)
SELECT
  icu_use,
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY COALESCE(c.count_studies, 0)) AS median,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY COALESCE(c.count_studies, 0)) AS q1,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY COALESCE(c.count_studies, 0)) AS q3,
  (PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY COALESCE(c.count_studies, 0)) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY COALESCE(c.count_studies, 0))) AS iqr
FROM los_icu l
LEFT JOIN ct_mri_count c ON l.hadm_id = c.hadm_id
GROUP BY icu_use, los_group;