WITH cohort AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE (p.gender = 'M' OR UPPER(p.gender) = 'MALE')
    AND p.anchor_age BETWEEN 36 AND 46
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd2
        ON di2.icd_code = dd2.icd_code AND di2.icd_version = dd2.icd_version
      WHERE di2.hadm_id = a.hadm_id
        AND LOWER(dd2.long_title) LIKE '%heart failure%'
    )
),

-- Part 2: First 48h antidiabetic and cardiac flags per admission
first48 AS (
  SELECT c.hadm_id,
         MAX(CASE
               WHEN LOWER(di.category) LIKE '%antidiabetic%' OR
                    LOWER(di.label) LIKE '%insulin%' OR
                    LOWER(di.label) LIKE '%metformin%'
               THEN 1 ELSE 0 END) AS antidiabetic_first48,
         MAX(CASE
               WHEN LOWER(di.category) LIKE '%cardiac%' OR
                    LOWER(di.category) LIKE '%cardiovascular%' OR
                    LOWER(di.label) LIKE '%beta blocker%' OR
                    LOWER(di.label) LIKE '%diuretic%' OR
                    LOWER(di.label) LIKE '%ACE inhibitor%' OR
                    LOWER(di.label) LIKE '%ARB%'
               THEN 1 ELSE 0 END) AS cardiac_first48
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS i
    ON i.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON i.itemid = di.itemid
  WHERE i.starttime >= c.admittime
    AND i.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.hadm_id
),

-- Part 3: Last 12h antidiabetic and cardiac flags per admission
last12 AS (
  SELECT c.hadm_id,
         MAX(CASE
               WHEN LOWER(di.category) LIKE '%antidiabetic%' OR
                    LOWER(di.label) LIKE '%insulin%' OR
                    LOWER(di.label) LIKE '%metformin%'
               THEN 1 ELSE 0 END) AS antidiabetic_last12,
         MAX(CASE
               WHEN LOWER(di.category) LIKE '%cardiac%' OR
                    LOWER(di.category) LIKE '%cardiovascular%' OR
                    LOWER(di.label) LIKE '%beta blocker%' OR
                    LOWER(di.label) LIKE '%diuretic%' OR
                    LOWER(di.label) LIKE '%ACE inhibitor%' OR
                    LOWER(di.label) LIKE '%ARB%'
               THEN 1 ELSE 0 END) AS cardiac_last12
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS i
    ON i.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON i.itemid = di.itemid
  WHERE i.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
    AND i.starttime <= c.dischtime
  GROUP BY c.hadm_id
)

-- Part 4: Compute prevalence and difference for each drug class
SELECT
  'antidiabetic' AS drug_class,
  ROUND(100.0 * SUM(COALESCE(a.antidiabetic_first48, 0)) / COUNT(*), 2) AS first48_prev_pct,
  ROUND(100.0 * SUM(COALESCE(b.antidiabetic_last12, 0)) / COUNT(*), 2) AS last12_prev_pct,
  ROUND((100.0 * SUM(COALESCE(a.antidiabetic_first48, 0)) / COUNT(*)) -
        (100.0 * SUM(COALESCE(b.antidiabetic_last12, 0)) / COUNT(*)), 2) AS diff_pp
FROM cohort c
LEFT JOIN first48 a ON a.hadm_id = c.hadm_id
LEFT JOIN last12 b ON b.hadm_id = c.hadm_id
UNION ALL
SELECT
  'cardiac' AS drug_class,
  ROUND(100.0 * SUM(COALESCE(a.cardiac_first48, 0)) / COUNT(*), 2) AS first48_prev_pct,
  ROUND(100.0 * SUM(COALESCE(b.cardiac_last12, 0)) / COUNT(*), 2) AS last12_prev_pct,
  ROUND((100.0 * SUM(COALESCE(a.cardiac_first48, 0)) / COUNT(*)) -
        (100.0 * SUM(COALESCE(b.cardiac_last12, 0)) / COUNT(*)), 2) AS diff_pp
FROM cohort c
LEFT JOIN first48 a ON a.hadm_id = c.hadm_id
LEFT JOIN last12 b ON b.hadm_id = c.hadm_id;