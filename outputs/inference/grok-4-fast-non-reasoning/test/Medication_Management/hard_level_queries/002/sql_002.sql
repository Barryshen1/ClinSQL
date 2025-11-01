WITH cohort AS (
  -- Base cohort: male, age 67-77, with principal AMI diagnosis
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    SAFE_CAST(p.anchor_age AS INT64) AS anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND SAFE_CAST(p.anchor_age AS INT64) BETWEEN 67 AND 77
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I21%'
    AND d.seq_num = 1  -- Principal diagnosis
),

med_scores AS (
  -- Medication complexity score: distinct medications in first 24h (via pharmacy for standardization)
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT ph.medication) AS score
  FROM 
    cohort c
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON c.hadm_id = ph.hadm_id
    AND ph.starttime >= c.admittime
    AND ph.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
    AND (ph.stoptime > c.admittime OR ph.stoptime IS NULL)
  GROUP BY 
    c.hadm_id
),

readmits AS (
  -- Flag 30-day readmission
  SELECT 
    c.hadm_id,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a_c
          ON a2.subject_id = a_c.subject_id
        WHERE a_c.hadm_id = c.hadm_id
          AND a2.hadm_id != c.hadm_id
          AND a2.admittime > a_c.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(a_c.dischtime, INTERVAL 30 DAY)
      ) THEN 1 
      ELSE 0 
    END AS has_readmit
  FROM 
    cohort c
),

final AS (
  SELECT 
    ms.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    r.has_readmit,
    COALESCE(ms.score, 0) AS score,
    -- Tertile assignment
    NTILE(3) OVER (ORDER BY COALESCE(ms.score, 0)) AS tertile
  FROM 
    cohort c
  LEFT JOIN 
    med_scores ms ON c.hadm_id = ms.hadm_id
  LEFT JOIN 
    readmits r ON c.hadm_id = r.hadm_id
)

-- Aggregate per tertile
SELECT 
  tertile,
  COUNT(hadm_id) AS admission_count,
  MIN(score) AS min_score,
  MAX(score) AS max_score,
  ROUND(AVG(score), 2) AS mean_score,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0), 2) AS mean_los_days,
  ROUND(
    (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)), 
    2
  ) AS in_hospital_mortality_pct,
  ROUND(
    (SUM(has_readmit) * 100.0 / COUNT(*)), 
    2
  ) AS readmission_30d_pct
FROM 
  final
GROUP BY 
  tertile
ORDER BY 
  tertile;