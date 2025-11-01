WITH
-- Define trauma ICD-10 codes (S00-T88)
trauma_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code BETWEEN 'S000' AND 'T889'
),

-- Get female patients aged 45-55 with multi-trauma
qualifying_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN trauma_codes t ON d.icd_code = t.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND a.admission_type != 'NEWBORN'
),

-- Calculate medication complexity for first 7 days
med_complexity AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    a.admittime,
    -- Count unique medications
    COUNT(DISTINCT p.medication) AS unique_meds,
    -- Count unique routes
    COUNT(DISTINCT p.route) AS unique_routes,
    -- Count unique frequencies
    COUNT(DISTINCT p.frequency) AS unique_frequencies,
    -- Total medication complexity score
    COUNT(DISTINCT p.medication) + COUNT(DISTINCT p.route) + COUNT(DISTINCT p.frequency) AS complexity_score
  FROM qualifying_patients q
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON q.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` p ON q.hadm_id = p.hadm_id
    AND p.starttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 7 DAY)
  GROUP BY q.subject_id, q.hadm_id, a.admittime
),

-- Add tertiles
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM med_complexity
),

-- Calculate outcomes
outcomes AS (
  SELECT
    t.tertile,
    COUNT(DISTINCT t.hadm_id) AS admission_count,
    AVG(t.complexity_score) AS mean_complexity,
    MIN(t.complexity_score) AS min_complexity,
    MAX(t.complexity_score) AS max_complexity,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS mean_los,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT t.hadm_id) AS mortality_rate,
    -- 30-day readmission calculation
    SUM(CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = t.subject_id
        AND a2.hadm_id != t.hadm_id
        AND a2.admittime BETWEEN a.dischtime AND DATETIME_ADD(a.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END) / COUNT(DISTINCT t.hadm_id) AS readmission_rate
  FROM tertiles t
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON t.hadm_id = a.hadm_id
  GROUP BY t.tertile
)

-- Final output
SELECT
  tertile,
  admission_count,
  mean_complexity,
  min_complexity,
  max_complexity,
  mean_los,
  ROUND(mortality_rate * 100, 2) AS mortality_percent,
  ROUND(readmission_rate * 100, 2) AS readmission_percent
FROM outcomes
ORDER BY tertile;