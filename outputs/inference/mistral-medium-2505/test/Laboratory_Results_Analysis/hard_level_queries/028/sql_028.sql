WITH
-- Define ICH diagnosis codes
ich_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN (
    '430', '431', '432',  -- ICD-9
    'I60', 'I61', 'I62'   -- ICD-10
  )
),

-- Get women aged 74-84 with ICH
ich_patients AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  JOIN ich_codes c ON d.icd_code = c.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
),

-- Get their admissions
ich_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN ich_patients p ON a.subject_id = p.subject_id
),

-- Get initial 72-hour labs
initial_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN ich_admissions a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE TIMESTAMP_DIFF(l.charttime, a.admittime, HOUR) <= 72
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
),

-- Identify abnormal labs
abnormal_labs AS (
  SELECT
    subject_id,
    hadm_id,
    itemid,
    CASE
      WHEN valuenum < ref_range_lower OR valuenum > ref_range_upper THEN 1
      ELSE 0
    END AS is_abnormal
  FROM initial_labs
),

-- Count distinct abnormal labs per patient
abnormal_counts AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT CASE WHEN is_abnormal = 1 THEN itemid END) AS distinct_abnormal_labs
  FROM abnormal_labs
  GROUP BY subject_id, hadm_id
),

-- Create quintiles
quintiles AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los_days,
    a.hospital_expire_flag,
    ac.distinct_abnormal_labs,
    NTILE(5) OVER (ORDER BY ac.distinct_abnormal_labs) AS lab_quintile
  FROM ich_admissions a
  JOIN abnormal_counts ac ON a.subject_id = ac.subject_id AND a.hadm_id = ac.hadm_id
),

-- Get age-matched controls (women 74-84 without ICH)
controls AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
    AND p.subject_id NOT IN (SELECT subject_id FROM ich_patients)
),

-- Get control admissions for lab comparison
control_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN controls c ON a.subject_id = c.subject_id
),

-- Get critical lab rates for comparison
critical_labs AS (
  SELECT
    'ICH' AS cohort,
    l.itemid,
    d.label,
    COUNT(DISTINCT l.subject_id) AS patient_count,
    COUNT(CASE WHEN al.is_abnormal = 1 THEN 1 END) AS abnormal_count,
    COUNT(CASE WHEN al.is_abnormal = 1 THEN 1 END) * 1.0 / COUNT(DISTINCT l.subject_id) AS abnormal_rate
  FROM initial_labs l
  JOIN abnormal_labs al ON l.subject_id = al.subject_id AND l.hadm_id = al.hadm_id AND l.itemid = al.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE l.itemid IN (50821, 50912, 50822) -- Example critical labs: hemoglobin, sodium, potassium
  GROUP BY l.itemid, d.label

  UNION ALL

  SELECT
    'Control' AS cohort,
    l.itemid,
    d.label,
    COUNT(DISTINCT l.subject_id) AS patient_count,
    COUNT(CASE WHEN al.is_abnormal = 1 THEN 1 END) AS abnormal_count,
    COUNT(CASE WHEN al.is_abnormal = 1 THEN 1 END) * 1.0 / COUNT(DISTINCT l.subject_id) AS abnormal_rate
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN control_admissions a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN (
    SELECT
      l.subject_id,
      l.hadm_id,
      l.itemid,
      l.valuenum,
      l.ref_range_lower,
      l.ref_range_upper,
      CASE
        WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1
        ELSE 0
      END AS is_abnormal
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN control_admissions a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
    WHERE l.itemid IN (50821, 50912, 50822)
      AND l.valuenum IS NOT NULL
      AND l.ref_range_lower IS NOT NULL
      AND l.ref_range_upper IS NOT NULL
      AND TIMESTAMP_DIFF(l.charttime, a.admittime, HOUR) <= 72
  ) al ON l.subject_id = al.subject_id AND l.hadm_id = al.hadm_id AND l.itemid = al.itemid
  WHERE l.itemid IN (50821, 50912, 50822)
  GROUP BY l.itemid, d.label
)

-- Final results
SELECT
  lab_quintile,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(distinct_abnormal_labs) AS avg_abnormal_labs,
  AVG(los_days) AS avg_los_days,
  SUM(hospital_expire_flag) * 1.0 / COUNT(DISTINCT subject_id) AS mortality_rate
FROM quintiles
GROUP BY lab_quintile
ORDER BY lab_quintile;

-- Critical lab comparison
SELECT * FROM critical_labs
ORDER BY cohort, itemid;