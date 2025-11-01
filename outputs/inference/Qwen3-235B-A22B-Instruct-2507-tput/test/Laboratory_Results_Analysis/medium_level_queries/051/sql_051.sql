WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 80 AND 90
),
acs_admissions AS (
  SELECT DISTINCT pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime, pa.los_days
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%myocardial infarction%'
     OR LOWER(d.long_title) LIKE '%acute coronary syndrome%'
     OR LOWER(d.long_title) LIKE '%unstable angina%'
     OR (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code = 'I20.0')
),
hstnt_labitem AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems
  WHERE (LOWER(label) LIKE '%troponin%t%high%sen%'
     OR LOWER(label) LIKE '%high%sen%troponin%t%'
     OR loinc_code = '46934-7')
),
first_hstnt AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents l
  INNER JOIN hstnt_labitem hli ON l.itemid = hli.itemid
  WHERE l.valuenum IS NOT NULL
),
classified_troponin AS (
  SELECT 
    aa.hadm_id,
    aa.los_days,
    CASE
      WHEN f.valuenum <= 14 THEN 'Normal'
      WHEN f.valuenum BETWEEN 15 AND 59 THEN 'Borderline'
      WHEN f.valuenum >= 60 THEN 'Myocardial Injury'
      ELSE 'Unknown'
    END AS troponin_category
  FROM acs_admissions aa
  INNER JOIN first_hstnt f ON aa.hadm_id = f.hadm_id
  WHERE f.rn = 1
),
summary AS (
  SELECT
    troponin_category,
    COUNT(*) AS count_patients,
    AVG(los_days) AS mean_los_days
  FROM classified_troponin
  GROUP BY troponin_category
),
totals AS (
  SELECT SUM(count_patients) AS total_count
  FROM summary
)
SELECT
  s.troponin_category,
  s.count_patients,
  ROUND(s.count_patients * 100.0 / t.total_count, 2) AS percentage,
  ROUND(s.mean_los_days, 2) AS mean_los_days
FROM summary s
CROSS JOIN totals t
ORDER BY s.troponin_category;