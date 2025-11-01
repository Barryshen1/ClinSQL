WITH dka_icd_codes AS (
  -- DKA ICD codes (ICD-9 and ICD-10)
  SELECT '25010' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '25011', 9 UNION ALL
  SELECT '25012', 9 UNION ALL
  SELECT '25013', 9 UNION ALL
  SELECT 'E101', 10 UNION ALL
  SELECT 'E111', 10 UNION ALL
  SELECT 'E131', 10
),
dka_admissions AS (
  -- Find admissions with DKA diagnosis
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN dka_icd_codes c
    ON d.icd_code = c.icd_code AND d.icd_version = c.icd_version
),
male_icu_stays AS (
  -- Male ICU stays, age 39-49, with DKA
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON icu.subject_id = p.subject_id
  JOIN dka_admissions dka
    ON icu.subject_id = dka.subject_id AND icu.hadm_id = dka.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),
first_icu_stays AS (
  -- Only first ICU stay per hospital admission
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM male_icu_stays
  )
  WHERE rn = 1
),
proc_in_24h AS (
  -- Procedures in first 24h of ICU stay
  SELECT
    f.stay_id,
    f.subject_id,
    f.hadm_id,
    f.intime,
    f.outtime,
    f.los,
    pr.icd_code
  FROM first_icu_stays f
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd pr
    ON f.subject_id = pr.subject_id
    AND f.hadm_id = pr.hadm_id
    AND pr.chartdate >= DATE(f.intime)
    AND pr.chartdate < DATE_ADD(DATE(f.intime), INTERVAL 1 DAY)
),
proc_counts AS (
  -- Count distinct procedures per stay
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    intime,
    outtime,
    los,
    COUNT(DISTINCT icd_code) AS proc_count
  FROM proc_in_24h
  GROUP BY stay_id, subject_id, hadm_id, intime, outtime, los
),
add_mortality AS (
  -- Add hospital mortality flag
  SELECT
    pc.*,
    a.hospital_expire_flag
  FROM proc_counts pc
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON pc.hadm_id = a.hadm_id
),
with_quintile AS (
  -- Assign quintiles by procedure count
  SELECT
    *,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM add_mortality
)
SELECT
  quintile,
  COUNT(*) AS n_stays,
  ROUND(AVG(proc_count),2) AS mean_proc_count,
  MIN(proc_count) AS min_proc_count,
  MAX(proc_count) AS max_proc_count,
  ROUND(AVG(los),2) AS mean_icu_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*),2) AS hospital_mortality_pct
FROM with_quintile
GROUP BY quintile
ORDER BY quintile;