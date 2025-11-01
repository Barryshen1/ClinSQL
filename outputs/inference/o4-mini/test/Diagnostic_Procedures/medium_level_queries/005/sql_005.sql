WITH stroke_admissions AS (
  -- Step 1 & 2: Filter for 49–59 y.o. females and classify primary vs. secondary stroke
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    -- Compute length of stay in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Classify as primary or secondary stroke
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code = dd.icd_code
         AND d.icd_version = dd.icd_version
        WHERE d.hadm_id = a.hadm_id
          AND LOWER(dd.long_title) LIKE '%ischemic stroke%'
          AND d.seq_num = 1
      ) THEN 'primary'
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code = dd.icd_code
         AND d.icd_version = dd.icd_version
        WHERE d.hadm_id = a.hadm_id
          AND LOWER(dd.long_title) LIKE '%ischemic stroke%'
          AND d.seq_num > 1
      ) THEN 'secondary'
      ELSE NULL
    END AS dx_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
),

proc_counts AS (
  -- Step 5: Count procedures per admission (0 if none)
  SELECT
    sa.hadm_id,
    sa.los_days,
    sa.dx_type,
    COUNT(pi.icd_code) AS proc_count
  FROM stroke_admissions sa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON sa.hadm_id = pi.hadm_id
  WHERE sa.los_days BETWEEN 1 AND 8
    AND sa.dx_type IS NOT NULL
  GROUP BY sa.hadm_id, sa.los_days, sa.dx_type
)

-- Step 6: Aggregate by LOS bin and diagnosis type
SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
    WHEN los_days BETWEEN 5 AND 8 THEN '5-8'
  END AS los_bin,
  dx_type AS diagnosis_group,
  ROUND(AVG(proc_count), 2) AS mean_procedures,
  MIN(proc_count) AS min_procedures,
  MAX(proc_count) AS max_procedures
FROM proc_counts
WHERE los_days BETWEEN 1 AND 8
  AND dx_type IS NOT NULL
GROUP BY los_bin, diagnosis_group
ORDER BY los_bin, diagnosis_group;