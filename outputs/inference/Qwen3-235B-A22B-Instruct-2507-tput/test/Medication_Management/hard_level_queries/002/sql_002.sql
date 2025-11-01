WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 67 AND 77
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
        ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
      WHERE diag.hadm_id = a.hadm_id
        AND d_diag.icd_version = 10
        AND (d_diag.icd_code LIKE 'I21%' OR d_diag.icd_code LIKE 'I22%')
    )
),
medication_complexity AS (
  SELECT
    ea.hadm_id,
    ea.subject_id,
    ea.admittime,
    ea.dischtime,
    ea.hospital_expire_flag,
    ea.age_at_admit,
    -- Count distinct drugs in first 24h of admission
    COUNT(DISTINCT pr.drug) AS med_count
  FROM eligible_admissions ea
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ea.hadm_id = pr.hadm_id
    AND pr.starttime >= ea.admittime
    AND pr.starttime < DATETIME_ADD(ea.admittime, INTERVAL 1 DAY)
    AND pr.drug IS NOT NULL
  GROUP BY ea.hadm_id, ea.subject_id, ea.admittime, ea.dischtime, ea.hospital_expire_flag, ea.age_at_admit
),
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_count) AS tertile
  FROM medication_complexity
),
readmission_flag AS (
  SELECT
    t.*,
    -- Check if next admission is within 30 days
    LEAD(t.admittime) OVER (PARTITION BY t.subject_id ORDER BY t.admittime) AS next_admittime
  FROM tertiles t
),
readmission_stats AS (
  SELECT
    *,
    CASE 
      WHEN next_admittime IS NOT NULL 
        AND next_admittime <= DATETIME_ADD(dischtime, INTERVAL 30 DAY) 
      THEN 1 ELSE 0 
    END AS thirty_day_readmit
  FROM readmission_flag
),
summary AS (
  SELECT
    tertile,
    COUNT(*) AS admission_count,
    MIN(med_count) AS score_min,
    MAX(med_count) AS score_max,
    AVG(med_count) AS score_mean,
    AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / 86400.0) AS mean_los_days,
    AVG(hospital_expire_flag) * 100 AS mortality_pct,
    AVG(thirty_day_readmit) * 100 AS readmission_30day_pct
  FROM readmission_stats
  GROUP BY tertile
)
SELECT
  tertile,
  admission_count,
  CONCAT(CAST(score_min AS STRING), ' - ', CAST(score_max AS STRING)) AS score_range,
  ROUND(score_mean, 2) AS score_mean,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(mortality_pct, 2) AS mortality_pct,
  ROUND(readmission_30day_pct, 2) AS readmission_30day_pct
FROM summary
ORDER BY tertile;