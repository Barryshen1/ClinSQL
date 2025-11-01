WITH hemorrhagic_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10: I60-I62
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I6[0-2]'))
    -- ICD-9: 430-432
    OR (icd_version = 9 AND icd_code IN ('430', '431', '432'))
),

-- Step 2: Target cohort admissions (male, 40-50, hemorrhagic stroke)
target_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN hemorrhagic_icd h
    ON d.icd_code = h.icd_code AND d.icd_version = h.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

-- Step 3: General inpatient admissions (for comparison)
general_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age IS NOT NULL AND p.gender IS NOT NULL
),

-- Step 4: Lab instability score for each admission (first 72h)
lab_abnormal AS (
  SELECT
    l.hadm_id,
    l.itemid,
    MIN(l.charttime) AS first_abnormal_time
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON l.hadm_id = a.hadm_id
  WHERE
    l.flag IN ('abnormal', 'high', 'low')
    AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY l.hadm_id, l.itemid
),

-- Step 5: Lab instability score per admission (target cohort)
target_instability AS (
  SELECT
    ta.hadm_id,
    COUNT(DISTINCT la.itemid) AS instability_score
  FROM target_admissions ta
  LEFT JOIN lab_abnormal la
    ON ta.hadm_id = la.hadm_id
  GROUP BY ta.hadm_id
),

-- Step 6: Lab instability score per admission (general cohort)
general_instability AS (
  SELECT
    ga.hadm_id,
    COUNT(DISTINCT la.itemid) AS instability_score
  FROM general_admissions ga
  LEFT JOIN lab_abnormal la
    ON ga.hadm_id = la.hadm_id
  GROUP BY ga.hadm_id
),

-- Step 7: Quartiles for target cohort
target_quartiles AS (
  SELECT
    instability_score,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile,
    hadm_id
  FROM target_instability
),

-- Step 8: LOS and mortality for target cohort
target_outcomes AS (
  SELECT
    tq.quartile,
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(TIMESTAMP_DIFF(ta.dischtime, ta.admittime, HOUR)/24, 2)[OFFSET(1)] AS median_los_days,
    SUM(CASE
      WHEN ta.hospital_expire_flag = 1
        OR (ta.deathtime IS NOT NULL AND ta.deathtime BETWEEN ta.admittime AND ta.dischtime)
      THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
  FROM target_quartiles tq
  JOIN target_admissions ta
    ON tq.hadm_id = ta.hadm_id
  GROUP BY tq.quartile
),

-- Step 9: Per-lab abnormal rates (target cohort, first 72h)
target_lab_rates AS (
  SELECT
    dl.label AS lab_name,
    COUNT(DISTINCT la.hadm_id) AS n_abnormal,
    COUNT(DISTINCT ta.hadm_id) AS n_total,
    COUNT(DISTINCT la.hadm_id) / COUNT(DISTINCT ta.hadm_id) AS abnormal_rate
  FROM target_admissions ta
  LEFT JOIN lab_abnormal la
    ON ta.hadm_id = la.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON la.itemid = dl.itemid
  GROUP BY dl.label
  HAVING n_total > 0
),

-- Step 10: LOS and mortality for general cohort
general_outcomes AS (
  SELECT
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(TIMESTAMP_DIFF(ga.dischtime, ga.admittime, HOUR)/24, 2)[OFFSET(1)] AS median_los_days,
    SUM(CASE
      WHEN ga.hospital_expire_flag = 1
        OR (ga.deathtime IS NOT NULL AND ga.deathtime BETWEEN ga.admittime AND ga.dischtime)
      THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
  FROM general_admissions ga
),

-- Step 11: Per-lab abnormal rates (general cohort, first 72h)
general_lab_rates AS (
  SELECT
    dl.label AS lab_name,
    COUNT(DISTINCT la.hadm_id) AS n_abnormal,
    COUNT(DISTINCT ga.hadm_id) AS n_total,
    COUNT(DISTINCT la.hadm_id) / COUNT(DISTINCT ga.hadm_id) AS abnormal_rate
  FROM general_admissions ga
  LEFT JOIN lab_abnormal la
    ON ga.hadm_id = la.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON la.itemid = dl.itemid
  GROUP BY dl.label
  HAVING n_total > 0
)

-- Final output: Target cohort quartiles, general cohort, and per-lab rates
SELECT 'target_quartiles' AS section, tq.quartile, NULL AS lab_name, NULL AS n_abnormal, NULL AS n_total, NULL AS abnormal_rate, t_out.n_admissions, t_out.median_los_days, t_out.mortality_rate
FROM target_outcomes t_out
JOIN target_quartiles tq ON t_out.quartile = tq.quartile
GROUP BY t_out.quartile, tq.quartile, t_out.n_admissions, t_out.median_los_days, t_out.mortality_rate

UNION ALL

SELECT 'general_cohort' AS section, NULL AS quartile, NULL AS lab_name, NULL AS n_abnormal, NULL AS n_total, NULL AS abnormal_rate, go.n_admissions, go.median_los_days, go.mortality_rate
FROM general_outcomes go

UNION ALL

SELECT 'target_lab_rates' AS section, NULL AS quartile, tlr.lab_name, tlr.n_abnormal, tlr.n_total, tlr.abnormal_rate, NULL AS n_admissions, NULL AS median_los_days, NULL AS mortality_rate
FROM target_lab_rates tlr

UNION ALL

SELECT 'general_lab_rates' AS section, NULL AS quartile, glr.lab_name, glr.n_abnormal, glr.n_total, glr.abnormal_rate, NULL AS n_admissions, NULL AS median_los_days, NULL AS mortality_rate
FROM general_lab_rates glr

ORDER BY section, quartile, lab_name;