WITH cohort_all AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.gender,
    (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2 
        WHERE di2.hadm_id = a.hadm_id 
          AND CAST(di2.seq_num AS INT64) > 1 
          AND (
            (di2.icd_version = 9 AND (
              di2.icd_code LIKE '428%' OR 
              di2.icd_code LIKE '785.5%' OR 
              di2.icd_code LIKE '427%'
            )) OR 
            (di2.icd_version = 10 AND (
              di2.icd_code LIKE 'I50%' OR 
              di2.icd_code LIKE 'R57%' OR 
              di2.icd_code LIKE 'I48%' OR 
              di2.icd_code LIKE 'I49%'
            ))
          )
      ) THEN 1 
      ELSE 0 
    END AS has_major_comp,
    (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + 
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2 
        WHERE di2.hadm_id = a.hadm_id 
          AND CAST(di2.seq_num AS INT64) > 1 
          AND (
            (di2.icd_version = 9 AND (
              di2.icd_code LIKE '428%' OR 
              di2.icd_code LIKE '785.5%' OR 
              di2.icd_code LIKE '427%'
            )) OR 
            (di2.icd_version = 10 AND (
              di2.icd_code LIKE 'I50%' OR 
              di2.icd_code LIKE 'R57%' OR 
              di2.icd_code LIKE 'I48%' OR 
              di2.icd_code LIKE 'I49%'
            ))
          )
      ) THEN 1 
      ELSE 0 
    END AS risk_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id AND p.subject_id = di.subject_id
  WHERE 
    p.gender = 'M'
    AND CAST(di.seq_num AS INT64) = 1
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '410%') OR 
      (di.icd_version = 10 AND di.icd_code LIKE 'I21%')
    )
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 46 AND 56
    AND a.admittime IS NOT NULL 
    AND a.dischtime IS NOT NULL
),
quintiled AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY risk_score ASC) AS quintile
  FROM cohort_all
),
stats AS (
  SELECT 
    quintile,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct,
    ROUND(100.0 * SUM(has_major_comp) / COUNT(*), 2) AS major_comp_pct
  FROM quintiled
  GROUP BY quintile
),
survivors AS (
  SELECT 
    quintile,
    los_days
  FROM quintiled
  WHERE hospital_expire_flag = 0
),
median_los AS (
  SELECT 
    quintile,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days
  FROM survivors
  GROUP BY quintile
)
SELECT 
  s.quintile,
  s.mortality_pct,
  s.major_comp_pct,
  m.median_los_days AS median_survivor_los
FROM stats s
INNER JOIN median_los m ON s.quintile = m.quintile
ORDER BY s.quintile;