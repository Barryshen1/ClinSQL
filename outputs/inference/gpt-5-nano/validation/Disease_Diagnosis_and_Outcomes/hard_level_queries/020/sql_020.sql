WITH mi_admissions AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE (dd.long_title LIKE '%myocardial infarction%')
     OR (di.icd_version = 9 AND di.icd_code LIKE '410%')
     OR (di.icd_version = 9 AND di.icd_code LIKE '412%')
     OR (di.icd_version = 10 AND di.icd_code LIKE 'I21%')
     OR (di.icd_version = 10 AND di.icd_code LIKE 'I22%')
),
cohort_base AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_adm,
    (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS los_days,
    CASE WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS in_hosp_mort,
    COALESCE(mc.major_complications_count, 0) AS major_complications_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  LEFT JOIN (
    -- Major complications: counts of diagnoses whose long_title contains key terms
    SELECT di.hadm_id, COUNT(*) AS major_complications_count
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
    WHERE LOWER(dd.long_title) LIKE '%shock%'
       OR LOWER(dd.long_title) LIKE '%heart failure%'
       OR LOWER(dd.long_title) LIKE '%arrhythmia%'
       OR LOWER(dd.long_title) LIKE '%arrest%'
       OR LOWER(dd.long_title) LIKE '%renal%'
       OR LOWER(dd.long_title) LIKE '%kidney%'
       OR LOWER(dd.long_title) LIKE '%embolism%'
       OR LOWER(dd.long_title) LIKE '%infection%'
    GROUP BY di.hadm_id
  ) mc ON mc.hadm_id = a.hadm_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM mi_admissions)
    AND LOWER(p.gender) = 'm'
    -- age at admission between 46 and 56 inclusive
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 46 AND 56
    -- ensure discharge times exist
    AND a.dischtime IS NOT NULL
),
cohort_with_risk AS (
  SELECT
    *,
    (age_at_adm + major_complications_count) AS risk_score
  FROM cohort_base
),
quintiled AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM cohort_with_risk
)
SELECT
  q.quintile,
  ROUND(AVG(q.in_hosp_mort) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(CASE WHEN q.major_complications_count > 0 THEN 1 ELSE 0 END) * 100, 2) AS major_complication_pct,
  med.median_survivor_los_days
FROM quintiled q
LEFT JOIN (
  -- Median LOS among survivors (in_hosp_mort = 0) per quintile using approximate quantiles
  SELECT quintile,
         APPROX_QUANTILES(los_days, 1001)[OFFSET(500)] AS median_survivor_los_days
  FROM quintiled
  WHERE in_hosp_mort = 0
  GROUP BY quintile
) AS med
  ON med.quintile = q.quintile
GROUP BY q.quintile, med.median_survivor_los_days
ORDER BY q.quintile;