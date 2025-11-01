WITH cohort AS (
  -- Step 1: male inpatients age 49–59
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.hospital_expire_flag IN (0,1)
),
dx AS (
  -- T2DM diagnoses
  SELECT DISTINCT hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%type 2 diabetes%'
),
hf AS (
  -- Heart failure diagnoses
  SELECT DISTINCT hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%heart failure%'
),
cohort2 AS (
  -- Restrict to those with both conditions
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime
  FROM cohort c
  JOIN dx ON c.hadm_id = dx.hadm_id
  JOIN hf ON c.hadm_id = hf.hadm_id
),
med_events AS (
  -- Step 2: prescriptions in first 24h and final 48h, with classes
  SELECT
    c.hadm_id,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(p.drug), r'(metformin|insulin|glipizide|glyburide|sitagliptin)') THEN 'Antidiabetic'
      WHEN REGEXP_CONTAINS(LOWER(p.drug), r'(metoprolol|atenolol|propranolol|carvedilol)') THEN 'Beta-Blocker'
      WHEN REGEXP_CONTAINS(LOWER(p.drug), r'(lisinopril|enalapril|losartan|valsartan|sacubitril)') THEN 'ACEi/ARB/ARNI'
      WHEN REGEXP_CONTAINS(LOWER(p.drug), r'(furosemide|bumetanide|torsemide)') THEN 'Loop Diuretic'
      ELSE NULL
    END AS med_class,
    IF(p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 24 HOUR, 1, 0) AS first_flag,
    IF(p.starttime BETWEEN c.dischtime - INTERVAL 48 HOUR AND c.dischtime, 1, 0) AS final_flag
  FROM
    cohort2 c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON c.hadm_id = p.hadm_id
  WHERE
    p.starttime IS NOT NULL
    AND (
      p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 24 HOUR
      OR p.starttime BETWEEN c.dischtime - INTERVAL 48 HOUR AND c.dischtime
    )
    AND p.drug IS NOT NULL
),
flags AS (
  -- Step 3: collapse to one row per hadm_id & class
  SELECT
    hadm_id,
    med_class,
    MAX(first_flag) AS first_flag,
    MAX(final_flag) AS final_flag
  FROM med_events
  WHERE med_class IS NOT NULL
  GROUP BY hadm_id, med_class
),
classify AS (
  -- Step 4: continued / initiated / discontinued
  SELECT
    hadm_id,
    med_class,
    first_flag,
    final_flag,
    CASE WHEN first_flag = 1 AND final_flag = 1 THEN 1 ELSE 0 END AS continued_flag,
    CASE WHEN first_flag = 0 AND final_flag = 1 THEN 1 ELSE 0 END AS initiated_flag,
    CASE WHEN first_flag = 1 AND final_flag = 0 THEN 1 ELSE 0 END AS discontinued_flag
  FROM flags
),
totals AS (
  -- total admissions in cohort
  SELECT COUNT(DISTINCT hadm_id) AS total_n
  FROM cohort2
)
-- Step 5: aggregate by medication class
SELECT
  mc.med_class,
  ROUND(100.0 * SUM(mc.first_flag) / t.total_n, 1)     AS first_24h_pct,
  ROUND(100.0 * SUM(mc.final_flag) / t.total_n, 1)     AS final_48h_pct,
  SUM(mc.continued_flag)      AS continued_count,
  SUM(mc.initiated_flag)      AS initiated_count,
  SUM(mc.discontinued_flag)   AS discontinued_count,
  t.total_n                   AS cohort_size
FROM
  classify mc
  CROSS JOIN totals t
GROUP BY
  mc.med_class, t.total_n
ORDER BY
  mc.med_class;