WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays i ON a.hadm_id = i.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d1 ON a.hadm_id = d1.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd1 ON d1.icd_code = dicd1.icd_code AND d1.icd_version = dicd1.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d2 ON a.hadm_id = d2.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd2 ON d2.icd_code = dicd2.icd_code AND d2.icd_version = dicd2.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND LOWER(dicd1.long_title) LIKE '%type 2 diabetes%'
    AND LOWER(dicd2.long_title) LIKE '%heart failure%'
),

meds_first_24h AS (
  SELECT
    c.stay_id,
    CASE
      WHEN LOWER(e.medication) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(e.medication) IN UNNEST(['metformin', 'glyburide', 'glipizide', 'glimepiride', 'sitagliptin', 'linagliptin', 'empagliflozin', 'dapagliflozin']) THEN 'oral'
    END AS med_class,
    e.medication,
    e.charttime,
    e.emar_id
  FROM
    cohort c
  JOIN
    physionet-data.mimiciv_3_1_hosp.emar e ON c.hadm_id = e.hadm_id
  WHERE
    e.charttime BETWEEN c.intime AND c.intime + INTERVAL 1 DAY
),

meds_last_48h AS (
  SELECT
    c.stay_id,
    CASE
      WHEN LOWER(e.medication) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(e.medication) IN UNNEST(['metformin', 'glyburide', 'glipizide', 'glimepiride', 'sitagliptin', 'linagliptin', 'empagliflozin', 'dapagliflozin']) THEN 'oral'
    END AS med_class,
    e.medication,
    e.charttime,
    e.emar_id
  FROM
    cohort c
  JOIN
    physionet-data.mimiciv_3_1_hosp.emar e ON c.hadm_id = e.hadm_id
  WHERE
    e.charttime BETWEEN c.outtime - INTERVAL 2 DAY AND c.outtime
),

med_status AS (
  SELECT
    c.stay_id,
    p.drug,
    p.starttime,
    p.stoptime,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(p.drug) IN UNNEST(['metformin', 'glyburide', 'glipizide', 'glimepiride', 'sitagliptin', 'linagliptin', 'empagliflozin', 'dapagliflozin']) THEN 'oral'
    END AS med_class,
    CASE
      WHEN p.stoptime IS NULL THEN 'continued'
      WHEN p.starttime >= c.intime THEN 'initiated'
      ELSE 'discontinued'
    END AS status
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions p
  JOIN
    cohort c ON p.hadm_id = c.hadm_id
)

SELECT
  'First 24h' AS time_window,
  med_class,
  COUNT(DISTINCT stay_id) AS patient_count,
  ROUND(COUNT(DISTINCT stay_id) * 100.0 / (SELECT COUNT(DISTINCT stay_id) FROM cohort), 2) AS prevalence_pct
FROM
  meds_first_24h
WHERE
  med_class IS NOT NULL
GROUP BY
  med_class

UNION ALL

SELECT
  'Last 48h' AS time_window,
  med_class,
  COUNT(DISTINCT stay_id) AS patient_count,
  ROUND(COUNT(DISTINCT stay_id) * 100.0 / (SELECT COUNT(DISTINCT stay_id) FROM cohort), 2) AS prevalence_pct
FROM
  meds_last_48h
WHERE
  med_class IS NOT NULL
GROUP BY
  med_class

UNION ALL

SELECT
  CONCAT('Status_', status) AS time_window,
  med_class,
  COUNT(*) AS patient_count,
  NULL AS prevalence_pct
FROM
  med_status
WHERE
  med_class IS NOT NULL
GROUP BY
  med_class, status
ORDER BY
  time_window, med_class;