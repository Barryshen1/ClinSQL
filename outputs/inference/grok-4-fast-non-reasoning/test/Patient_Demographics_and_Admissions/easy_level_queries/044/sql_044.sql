WITH first_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag,
    a.admittime,
    a.dischtime,
    a.deathtime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),
qualifying_admissions AS (
  SELECT *
  FROM first_admissions
  WHERE rn = 1  -- Only first admission per patient
),
mortality_flags AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 
        OR (deathtime IS NOT NULL AND admittime <= deathtime AND deathtime <= dischtime)
      THEN 1.0 
      ELSE 0.0 
    END AS mortality
  FROM qualifying_admissions
)
SELECT 
  PERCENTILE_CONT(mortality, 0.25) OVER() AS p25_mortality
FROM mortality_flags;