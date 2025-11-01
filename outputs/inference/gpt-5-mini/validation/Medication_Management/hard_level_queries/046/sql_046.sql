WITH trauma_hadm AS (
  -- Identify hadm_ids with trauma / multiple-injury diagnoses (text-match heuristic)
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE (
    LOWER(dd.long_title) LIKE '%multiple%' AND (
      LOWER(dd.long_title) LIKE '%injury%' OR LOWER(dd.long_title) LIKE '%trauma%'
    )
  )
  OR LOWER(dd.long_title) LIKE '%polytrauma%'
  OR LOWER(dd.long_title) LIKE '%multiple trauma%'
  OR LOWER(dd.long_title) LIKE '%multiple injuries%'
),

cohort_admissions AS (
  -- Female patients age 45-55 with a trauma admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND a.hadm_id IN (SELECT hadm_id FROM trauma_hadm)
    AND a.admittime IS NOT NULL
),

meds_first7_raw AS (
  -- Collect medication names from multiple medication/order tables within first 7 days of admission
  SELECT DISTINCT ca.hadm_id,
         LOWER(TRIM(pr.drug)) AS med_name
  FROM cohort_admissions ca
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = ca.hadm_id
   AND pr.starttime BETWEEN ca.admittime AND TIMESTAMP_ADD(ca.admittime, INTERVAL 7 DAY)
  WHERE pr.drug IS NOT NULL
    AND TRIM(pr.drug) <> ''
  UNION DISTINCT
  SELECT DISTINCT ca.hadm_id,
         LOWER(TRIM(ph.medication)) AS med_name
  FROM cohort_admissions ca
  JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.hadm_id = ca.hadm_id
   AND ph.starttime BETWEEN ca.admittime AND TIMESTAMP_ADD(ca.admittime, INTERVAL 7 DAY)
  WHERE ph.medication IS NOT NULL
    AND TRIM(ph.medication) <> ''
  UNION DISTINCT
  SELECT DISTINCT ca.hadm_id,
         LOWER(TRIM(e.medication)) AS med_name
  FROM cohort_admissions ca
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON e.hadm_id = ca.hadm_id
   AND e.charttime BETWEEN ca.admittime AND TIMESTAMP_ADD(ca.admittime, INTERVAL 7 DAY)
  WHERE e.medication IS NOT NULL
    AND TRIM(e.medication) <> ''
),

meds_first7_count AS (
  -- Complexity score = count distinct medication names in first 7 days (0 if none)
  SELECT
    ca.hadm_id,
    COALESCE(COUNT(m.med_name), 0) AS complexity_score
  FROM cohort_admissions ca
  LEFT JOIN meds_first7_raw m
    ON ca.hadm_id = m.hadm_id
  GROUP BY ca.hadm_id
),

admissions_with_next AS (
  -- Add next admission time per subject (for 30-day readmission computation)
  SELECT
    a.*,
    LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),

cohort_with_metrics AS (
  -- Combine cohort, complexity score, LOS, mortality flag, and 30-day readmit flag
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ca.admittime,
    ca.dischtime,
    ca.hospital_expire_flag,
    mfc.complexity_score,
    -- LOS in fractional days; exclude rows with missing dischtime when computing LOS downstream
    SAFE_DIVIDE(TIMESTAMP_DIFF(ca.dischtime, ca.admittime, SECOND), 86400.0) AS los_days,
    -- determine next admission time using the full admissions sequence per subject
    awn.next_admittime,
    CASE
      WHEN awn.next_admittime IS NOT NULL
       AND ca.dischtime IS NOT NULL
       AND TIMESTAMP_DIFF(awn.next_admittime, ca.dischtime, SECOND) > 0
       AND TIMESTAMP_DIFF(awn.next_admittime, ca.dischtime, SECOND) <= 30 * 86400
      THEN 1 ELSE 0
    END AS readmit_within_30d
  FROM cohort_admissions ca
  LEFT JOIN meds_first7_count mfc
    ON ca.hadm_id = mfc.hadm_id
  LEFT JOIN admissions_with_next awn
    ON ca.hadm_id = awn.hadm_id
),

cohort_tertiles AS (
  -- Assign tertiles across the cohort based on complexity score (NTILE distributes approx-equal counts)
  SELECT
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS complexity_tertile
  FROM cohort_with_metrics
)

SELECT
  complexity_tertile AS tertile,
  COUNT(*) AS num_admissions,
  ROUND(AVG(complexity_score), 2) AS mean_complexity_score,
  MIN(complexity_score) AS min_complexity_score,
  MAX(complexity_score) AS max_complexity_score,
  -- mean LOS only for admissions with a discharge time (NULL los_days excluded by AVG)
  ROUND(AVG(los_days), 2) AS mean_los_days,
  -- mortality percent
  ROUND(100.0 * SUM(CAST(hospital_expire_flag AS INT64)) / COUNT(*), 2) AS mortality_percent,
  -- 30-day readmission percent
  ROUND(100.0 * SUM(CAST(readmit_within_30d AS INT64)) / COUNT(*), 2) AS readmit_30d_percent
FROM cohort_tertiles
-- If you want to exclude admissions without discharge when computing LOS and readmission,
-- they are already handled because los_days is NULL -> AVG ignores NULLs; readmit was defined to require dischtime.
GROUP BY complexity_tertile
ORDER BY complexity_tertile;