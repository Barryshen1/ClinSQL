WITH ami_codes AS (
  SELECT code 
  FROM UNNEST([
    'I21.0', 'I21.01', 'I21.02', 'I21.1', 'I21.11', 'I21.19', 
    'I21.2', 'I21.21', 'I21.29', 'I21.3', 'I21.4', 
    'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9'
  ]) AS code
),
index_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Compute age at admission with proper parentheses
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 67 AND 77
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code IN (SELECT code FROM ami_codes)
    )
),
all_admissions AS (
  SELECT 
    subject_id, 
    hadm_id, 
    admittime, 
    dischtime,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
readmission_flag AS (
  SELECT 
    ia.subject_id,
    ia.hadm_id,
    ia.admittime,
    ia.dischtime,
    ia.hospital_expire_flag,
    ia.age,
    CASE 
      WHEN aa.next_admittime IS NOT NULL 
        AND aa.next_admittime <= ia.dischtime + INTERVAL '30' DAY 
        THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM index_admissions ia
  JOIN all_admissions aa 
    ON ia.subject_id = aa.subject_id AND ia.hadm_id = aa.hadm_id
),
med_complexity AS (
  SELECT 
    ia.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM index_admissions ia
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON ia.hadm_id = pr.hadm_id
    AND pr.starttime <= ia.admittime + INTERVAL '24' HOUR
    AND (pr.stoptime >= ia.admittime OR pr.stoptime IS NULL)
  GROUP BY ia.hadm_id
),
combined AS (
  SELECT 
    rf.*,
    COALESCE(mc.complexity_score, 0) AS complexity_score,
    -- Calculate LOS in days using HOUR for better precision
    TIMESTAMP_DIFF(rf.dischtime, rf.admittime, HOUR) / 24.0 AS los_days
  FROM readmission_flag rf
  LEFT JOIN med_complexity mc ON rf.hadm_id = mc.hadm_id
),
tertiles AS (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM combined
)
SELECT
  tertile,
  COUNT(*) AS admission_count,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  AVG(complexity_score) AS avg_score,
  AVG(los_days) AS mean_los_days,
  (SUM(hospital_expire_flag) * 100.0 / COUNT(*)) AS mortality_pct,
  (SUM(readmitted_30d) * 100.0 / COUNT(*)) AS readmission_pct
FROM tertiles
GROUP BY tertile
ORDER BY tertile;