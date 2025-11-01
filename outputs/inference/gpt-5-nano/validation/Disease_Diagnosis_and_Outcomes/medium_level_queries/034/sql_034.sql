WITH eligible AS (
  -- Select female patients aged 70-80 at admission
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE LOWER(p.gender) IN ('f', 'female')
    AND p.anchor_age BETWEEN 70 AND 80
),
hf_admissions AS (
  -- Keep only admissions that have a heart failure diagnosis (deduplicate admissions)
  SELECT DISTINCT e.subject_id, e.hadm_id, e.admittime, e.dischtime, e.deathtime, e.hospital_expire_flag
  FROM eligible AS e
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON e.subject_id = di.subject_id
   AND e.hadm_id = di.hadm_id
  WHERE (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
     OR (di.icd_version = 9  AND di.icd_code LIKE '428%')
),
los_stats AS (
  SELECT
    CASE
      WHEN TIMESTAMP_DIFF(hf.dischtime, hf.admittime, DAY) < 8 THEN '<8'
      ELSE '>=8'
    END AS los_group,
    COUNT(*) AS N,
    SAFE_DIVIDE(
      SUM(CASE WHEN hf.hospital_expire_flag = 1 THEN 1 ELSE 0 END),
      COUNT(*)
    ) * 100 AS mortality_rate_pct,
    SUM(CASE WHEN hf.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths
  FROM hf_admissions hf
  GROUP BY los_group
),
median_death AS (
  -- Compute median time-to-death (in days) among non-survivors
  SELECT MEDIAN(TIMESTAMP_DIFF(hf.deathtime, hf.admittime, DAY)) AS median_time_to_death_days
  FROM hf_admissions hf
  WHERE hf.hospital_expire_flag = 1 AND hf.deathtime IS NOT NULL
)
SELECT
  l.los_group,
  l.N,
  l.deaths,
  l.mortality_rate_pct,
  m.median_time_to_death_days
FROM los_stats l
CROSS JOIN median_death m
ORDER BY l.los_group;