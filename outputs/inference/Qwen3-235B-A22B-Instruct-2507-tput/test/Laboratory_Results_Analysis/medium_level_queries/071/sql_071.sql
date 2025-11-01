WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission,
    a.admittime,
    a.dischtime,
    a.dischtime - a.admittime AS los_interval,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
),

-- Filter admissions with suspected ACS as primary diagnosis
acs_admissions AS (
  SELECT
    pa.*
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.seq_num = 1  -- Primary diagnosis
    AND d.icd_code LIKE 'I20%'
    OR d.icd_code LIKE 'I21%'
    OR d.icd_code LIKE 'I24%'
),

-- Get Troponin T lab events
troponin_labs AS (
  SELECT
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dli
    ON le.itemid = dli.itemid
  WHERE LOWER(dli.label) = 'troponin t'
    AND le.valuenum IS NOT NULL
    AND le.charttime IS NOT NULL
),

-- First Troponin T per admission
first_troponin AS (
  SELECT
    hadm_id,
    valuenum
  FROM troponin_labs
  WHERE rn = 1
),

-- Combine ACS admissions with first Troponin T
acs_with_troponin AS (
  SELECT
    aa.hadm_id,
    aa.los_days,
    ft.valuenum,
    CASE
      WHEN ft.valuenum <= 0.014 THEN 'Normal'
      WHEN ft.valuenum <= 0.029 THEN 'Borderline'
      WHEN ft.valuenum > 0.029 THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category
  FROM acs_admissions aa
  INNER JOIN first_troponin ft
    ON aa.hadm_id = ft.hadm_id
),

-- Final aggregation
summary AS (
  SELECT
    troponin_category,
    COUNT(*) AS count_patients,
    AVG(los_days) AS avg_los_days
  FROM acs_with_troponin
  GROUP BY troponin_category
),

totals AS (
  SELECT SUM(count_patients) AS total_count
  FROM summary
)

-- Final output: category, count, percentage, avg LOS
SELECT
  s.troponin_category,
  s.count_patients,
  ROUND(100.0 * s.count_patients / t.total_count, 2) AS percentage,
  ROUND(s.avg_los_days, 2) AS avg_los_days
FROM summary s
CROSS JOIN totals t
ORDER BY
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 4
  END;