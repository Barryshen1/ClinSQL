WITH
-- 1. Identify admissions with female patients age 51–61
female_adms AS (
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
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),

-- 2. Identify admissions with diabetes diagnosis
diabetes_adms AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%diabetes%'
),

-- 3. Identify admissions with acute heart failure diagnosis
ahf_adms AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%heart failure%'
    AND LOWER(dd.long_title) LIKE '%acute%'
),

-- 4. Define our cohort: female, age 51-61, with both diabetes and acute HF
cohort AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.dischtime
  FROM
    female_adms f
    INNER JOIN diabetes_adms dia
      ON f.hadm_id = dia.hadm_id
    INNER JOIN ahf_adms ahf
      ON f.hadm_id = ahf.hadm_id
),

-- 5. Medication exposures in windows
--    Classify each prescription as 'insulin' or 'oral'
med_presc AS (
  SELECT
    c.hadm_id,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      ELSE 'oral'
    END AS drug_class,
    p.starttime,
    p.stoptime
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON c.hadm_id = p.hadm_id
),

-- 6. Flags for exposure in first 48h
exp_48h AS (
  SELECT
    m.hadm_id,
    m.drug_class,
    1 AS on_48h
  FROM
    med_presc m
    JOIN cohort c
      ON m.hadm_id = c.hadm_id
  WHERE
    -- overlap prescription with first 48 hours
    m.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND m.stoptime > c.admittime
  GROUP BY
    m.hadm_id,
    m.drug_class
),

-- 7. Flags for exposure in final 24h
exp_24h AS (
  SELECT
    m.hadm_id,
    m.drug_class,
    1 AS on_24h
  FROM
    med_presc m
    JOIN cohort c
      ON m.hadm_id = c.hadm_id
  WHERE
    -- overlap prescription with last 24 hours
    m.starttime < c.dischtime
    AND m.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR)
  GROUP BY
    m.hadm_id,
    m.drug_class
),

-- 8. Build one row per admission & drug_class with both flags (default 0)
adm_drug_flags AS (
  SELECT
    c.hadm_id,
    dc.drug_class,
    IFNULL(e48.on_48h, 0)   AS on_48h,
    IFNULL(e24.on_24h, 0)   AS on_24h
  FROM
    cohort c
    CROSS JOIN (SELECT 'insulin' AS drug_class UNION ALL SELECT 'oral') dc
    LEFT JOIN exp_48h e48
      ON c.hadm_id = e48.hadm_id
     AND dc.drug_class = e48.drug_class
    LEFT JOIN exp_24h e24
      ON c.hadm_id = e24.hadm_id
     AND dc.drug_class = e24.drug_class
),

-- 9. Compute totals and summary statistics
summary AS (
  SELECT
    drug_class,
    COUNT(*)                            AS n_admissions,
    SUM(on_48h)                         AS n_on_48h,
    SUM(on_24h)                         AS n_on_24h,
    100.0 * SUM(on_48h) / COUNT(*)      AS pct_on_48h,
    100.0 * SUM(on_24h) / COUNT(*)      AS pct_on_24h,
    SUM(CASE WHEN on_48h = 1 AND on_24h = 1 THEN 1 ELSE 0 END) AS n_continued,
    SUM(CASE WHEN on_48h = 0 AND on_24h = 1 THEN 1 ELSE 0 END) AS n_initiated,
    SUM(CASE WHEN on_48h = 1 AND on_24h = 0 THEN 1 ELSE 0 END) AS n_discontinued
  FROM
    adm_drug_flags
  GROUP BY
    drug_class
)

SELECT
  drug_class           AS medication_type,
  n_admissions         AS total_admissions,
  n_on_48h             AS count_on_first_48h,
  ROUND(pct_on_48h,1)  AS pct_on_first_48h,
  n_on_24h             AS count_on_final_24h,
  ROUND(pct_on_24h,1)  AS pct_on_final_24h,
  n_continued          AS count_continued,
  n_initiated          AS count_initiated,
  n_discontinued       AS count_discontinued
FROM
  summary
ORDER BY
  medication_type;