WITH cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime,
    p.gender, p.anchor_age, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
    ON dx.icd_code = ddx.icd_code
    AND dx.icd_version = ddx.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND LOWER(ddx.long_title) LIKE '%ketoacidosis%'
),
meds_48h AS (
  SELECT c.subject_id, c.hadm_id,
    COUNT(DISTINCT LOWER(pr.drug)) AS complexity,
    -- Hyperkalemia-risk drug classes
    MAX(
      CASE
        WHEN LOWER(pr.drug) LIKE '%lisinopril%' THEN 1
        WHEN LOWER(pr.drug) LIKE '%enalapril%' THEN 1
        WHEN LOWER(pr.drug) LIKE '%captopril%' THEN 1
        WHEN LOWER(pr.drug) LIKE '%ramipril%' THEN 1
        WHEN LOWER(pr.drug) LIKE '%losartan%' THEN 1
        WHEN LOWER(pr.drug) LIKE '%valsartan%' THEN 1
        WHEN LOWER(pr.drug) LIKE '%spironolactone%' THEN 1
        WHEN LOWER(pr.drug) LIKE '%eplerenone%' THEN 1
        WHEN LOWER(pr.drug) LIKE '%amiloride%' THEN 1
        WHEN LOWER(pr.drug) LIKE '%triamterene%' THEN 1
        WHEN LOWER(pr.drug) LIKE '%trimethoprim%' THEN 1
        WHEN LOWER(pr.drug) LIKE '%ibuprofen%' THEN 1
        WHEN LOWER(pr.drug) LIKE '%naproxen%' THEN 1
        ELSE 0
      END
    ) AS hyperk_risk_flag
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND pr.starttime >= c.admittime
  GROUP BY c.subject_id, c.hadm_id
),
with_stats AS (
  SELECT c.subject_id, c.hadm_id, m.complexity, m.hyperk_risk_flag,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    c.hospital_expire_flag,
    PERCENT_RANK() OVER (ORDER BY m.complexity) AS complexity_percentile,
    NTILE(4) OVER (ORDER BY m.complexity DESC) AS complexity_quartile
  FROM cohort c
  JOIN meds_48h m
    ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
),
summary AS (
  SELECT
    hyperk_risk_flag,
    AVG(complexity) AS mean_complexity,
    AVG(complexity_percentile) AS mean_percentile,
    AVG(los_days) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM with_stats
  GROUP BY hyperk_risk_flag
),
top_quartile AS (
  SELECT
    AVG(los_days) AS mean_los_topQ,
    AVG(hospital_expire_flag) AS mortality_rate_topQ
  FROM with_stats
  WHERE complexity_quartile = 1 -- top quartile by complexity
)
SELECT
  s.hyperk_risk_flag,
  s.mean_complexity,
  s.mean_percentile,
  s.mean_los,
  s.mortality_rate,
  tq.mean_los_topQ,
  tq.mortality_rate_topQ
FROM summary s
CROSS JOIN top_quartile tq
ORDER BY s.hyperk_risk_flag DESC;