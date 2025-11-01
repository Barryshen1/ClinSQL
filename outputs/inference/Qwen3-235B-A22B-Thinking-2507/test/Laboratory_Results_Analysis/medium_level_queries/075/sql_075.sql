WITH cohort AS (
  SELECT 
    a.hadm_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 41 AND 51
),
primary_diagnosis AS (
  SELECT 
    di.hadm_id,
    di.icd_code,
    di.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.seq_num = 1
    AND (
      (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '7865%'))
      OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'R07%'))
    )
),
troponin_first AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    le.ref_range_upper,
    ROW_NUMBER() OVER (
      PARTITION BY le.hadm_id 
      ORDER BY le.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.label = 'Troponin T'
    AND le.valuenum IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
)
SELECT
  CASE
    WHEN valuenum <= ref_range_upper THEN 'normal'
    WHEN valuenum > ref_range_upper AND valuenum <= ref_range_upper * 3 THEN 'borderline'
    WHEN valuenum > ref_range_upper * 3 THEN 'elevated'
  END AS category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(valuenum), 2) AS mean_valuenum,
  ROUND(APPROX_QUANTILES(valuenum, 100)[OFFSET(50)], 2) AS median,
  ROUND(APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)], 2) AS iqr
FROM troponin_first tf
INNER JOIN cohort c ON tf.hadm_id = c.hadm_id
INNER JOIN primary_diagnosis pd ON tf.hadm_id = pd.hadm_id
WHERE tf.rn = 1
GROUP BY category
ORDER BY 
  CASE category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
  END;