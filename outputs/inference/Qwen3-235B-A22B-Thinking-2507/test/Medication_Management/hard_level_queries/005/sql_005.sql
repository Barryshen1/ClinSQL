WITH base AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('570', '5722'))
          OR (d.icd_version = 10 AND d.icd_code LIKE 'K72%')
        )
    )
),
complexity AS (
  SELECT 
    b.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM base b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON b.hadm_id = pr.hadm_id
    AND pr.starttime < b.admittime + INTERVAL '72' HOUR
    AND (pr.stoptime IS NULL OR pr.stoptime > b.admittime)
  GROUP BY b.hadm_id
),
base_with_readmit AS (
  SELECT 
    *,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM base
),
base_with_flags AS (
  SELECT 
    *,
    CASE 
      WHEN next_admittime <= dischtime + INTERVAL '30' DAY THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM base_with_readmit
),
full_data AS (
  SELECT 
    b.hadm_id,
    b.hospital_expire_flag,
    b.readmitted_30d,
    DATETIME_DIFF(b.dischtime, b.admittime, HOUR) / 24.0 AS los_days,
    c.complexity_score
  FROM base_with_flags b
  LEFT JOIN complexity c
    ON b.hadm_id = c.hadm_id
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY complexity_score) AS quintile
  FROM full_data
)
SELECT 
  quintile,
  COUNT(*) AS n,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  AVG(complexity_score) AS mean_score,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(readmitted_30d) * 100 AS readmission_pct
FROM quintiles
GROUP BY quintile
ORDER BY quintile;