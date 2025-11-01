WITH
-- 1. Base cohort: female patients age 84-94 with a hospital admission
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
),

-- 2. Identify admissions with any DKA diagnosis
dka_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      USING(icd_code, icd_version)
  WHERE
    LOWER(dd.long_title) LIKE '%diabetic ketoacidosis%'
),

-- 3. Filter cohort to those with DKA
cohort_dka AS (
  SELECT
    c.*
  FROM
    cohort c
    JOIN dka_admissions d
      USING(subject_id, hadm_id)
),

-- 4. Medication counts and hyperkalemia-risk flags in first 48h
med_counts AS (
  SELECT
    cd.subject_id,
    cd.hadm_id,
    COUNT(DISTINCT p.drug) AS complexity,
    COUNT(DISTINCT CASE
      WHEN LOWER(p.drug) IN (
        'spironolactone', 'triamterene',
        'lisinopril', 'enalapril', 'captopril',
        'losartan', 'valsartan', 'irbesartan'
      ) THEN p.drug
      ELSE NULL
    END) AS hk_risk_count,
    cd.admittime,
    cd.dischtime,
    cd.hospital_expire_flag
  FROM
    cohort_dka cd
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON cd.subject_id = p.subject_id
      AND cd.hadm_id = p.hadm_id
      AND p.starttime BETWEEN cd.admittime
                         AND TIMESTAMP_ADD(cd.admittime, INTERVAL 48 HOUR)
  GROUP BY
    cd.subject_id, cd.hadm_id, cd.admittime, cd.dischtime, cd.hospital_expire_flag
),

-- 5. Define interaction flag, compute LOS
with_flags AS (
  SELECT
    subject_id,
    hadm_id,
    complexity,
    CASE WHEN hk_risk_count >= 2 THEN 1 ELSE 0 END AS interaction_flag,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0 AS los_days,
    hospital_expire_flag
  FROM med_counts
),

-- 6. Compute complexity quartiles across cohort
quartiles AS (
  SELECT
    APPROX_QUANTILES(complexity, 4) AS qvals
  FROM with_flags
),

-- 7. Tag top-quartile admissions
tagged AS (
  SELECT
    w.*,
    q.qvals[OFFSET(3)] AS q3_threshold,
    CASE WHEN w.complexity >= q.qvals[OFFSET(3)] THEN 1 ELSE 0 END AS top_quartile
  FROM
    with_flags w,
    quartiles q
)

-- 8. Final summary: among top-quartile complexity, compare interaction vs no
SELECT
  interaction_flag,
  COUNT(*) AS n_admissions,
  ROUND(AVG(complexity), 2) AS avg_complexity,
  ROUND(APPROX_QUANTILES(complexity, 2)[OFFSET(1)], 2) AS median_complexity,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(SUM(hospital_expire_flag)/COUNT(*), 3) AS mortality_rate
FROM
  tagged
WHERE
  top_quartile = 1
GROUP BY
  interaction_flag
ORDER BY
  interaction_flag;