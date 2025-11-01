WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.gender, 
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.services`
    WHERE prev_service IS NULL 
      AND curr_service = 'Surgical'
  ) s ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),
med_complexity AS (
  SELECT 
    hadm_id, 
    MAX(daily_unique) AS complexity_score
  FROM (
    SELECT 
      e.hadm_id, 
      DATE(e.charttime) AS adm_day, 
      COUNT(DISTINCT e.medication) AS daily_unique
    FROM `physionet-data.mimiciv_3_1_hosp.emar` e
    INNER JOIN cohort c ON e.hadm_id = c.hadm_id
    GROUP BY e.hadm_id, adm_day
  )
  GROUP BY hadm_id
),
has_readmission AS (
  SELECT 
    c.hadm_id,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = c.subject_id
          AND a2.hadm_id != c.hadm_id
          AND a2.admittime > c.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1 
      ELSE 0 
    END AS has_readm_flag
  FROM cohort c
  WHERE c.hospital_expire_flag = 0
),
cohort_with_score AS (
  SELECT 
    c.*,
    COALESCE(m.complexity_score, 0) AS score,
    COALESCE(r.has_readm_flag, 0) AS has_readmission
  FROM cohort c
  LEFT JOIN med_complexity m ON c.hadm_id = m.hadm_id
  LEFT JOIN has_readmission r ON c.hadm_id = r.hadm_id
),
cohort_quartile AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY score) AS quartile
  FROM cohort_with_score
)
SELECT 
  quartile,
  COUNT(*) AS count_admissions,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(
    SAFE_DIVIDE(
      SUM(has_readmission), 
      COUNTIF(hospital_expire_flag = 0)
    ) * 100, 2
  ) AS readmission_30d_pct
FROM cohort_quartile
GROUP BY quartile
ORDER BY quartile;