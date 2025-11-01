WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 66 AND 76
    AND icu.los >= 3  -- >= 72 hours
    AND (
      LOWER(d_dx.long_title) LIKE '%diabetes%'
      OR LOWER(d_dx.long_title) LIKE '%heart failure%'
    )
  GROUP BY
    icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime, icu.los
  HAVING
    COUNT(DISTINCT CASE WHEN LOWER(d_dx.long_title) LIKE '%diabetes%' THEN 1 END) > 0
    AND COUNT(DISTINCT CASE WHEN LOWER(d_dx.long_title) LIKE '%heart failure%' THEN 1 END) > 0
),

meds_first_72h AS (
  SELECT
    ing.subject_id,
    ing.stay_id,
    di.label,
    CASE
      WHEN LOWER(di.label) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(di.label) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(di.label) LIKE '%glp%' THEN 'GLP-1 agonist'
      WHEN LOWER(di.label) LIKE '%sglt%' THEN 'SGLT-2 inhibitor'
      WHEN LOWER(di.label) LIKE '%sulfonylurea%' THEN 'Sulfonylurea'
      ELSE 'Other antidiabetic'
    END AS drug_class
  FROM
    `physionet-data.mimiciv_3_1_icu.ingredientevents` ing
  JOIN
    cohort c
    ON ing.stay_id = c.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ing.itemid = di.itemid
  WHERE
    ing.starttime BETWEEN c.intime AND c.intime + INTERVAL 72 HOUR
),

meds_last_24h AS (
  SELECT
    ing.subject_id,
    ing.stay_id,
    di.label,
    CASE
      WHEN LOWER(di.label) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(di.label) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(di.label) LIKE '%glp%' THEN 'GLP-1 agonist'
      WHEN LOWER(di.label) LIKE '%sglt%' THEN 'SGLT-2 inhibitor'
      WHEN LOWER(di.label) LIKE '%sulfonylurea%' THEN 'Sulfonylurea'
      ELSE 'Other antidiabetic'
    END AS drug_class
  FROM
    `physionet-data.mimiciv_3_1_icu.ingredientevents` ing
  JOIN
    cohort c
    ON ing.stay_id = c.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ing.itemid = di.itemid
  WHERE
    ing.starttime BETWEEN c.outtime - INTERVAL 24 HOUR AND c.outtime
),

first_72h_counts AS (
  SELECT
    drug_class,
    COUNT(*) AS cnt
  FROM
    meds_first_72h
  GROUP BY
    drug_class
),

last_24h_counts AS (
  SELECT
    drug_class,
    COUNT(*) AS cnt
  FROM
    meds_last_24h
  GROUP BY
    drug_class
),

first_72h_total AS (
  SELECT SUM(cnt) AS total FROM first_72h_counts
),

last_24h_total AS (
  SELECT SUM(cnt) AS total FROM last_24h_counts
)

SELECT
  'First 72h' AS time_window,
  f.drug_class,
  ROUND(SAFE_DIVIDE(f.cnt, t.total) * 100, 2) AS percentage
FROM
  first_72h_counts f
CROSS JOIN
  first_72h_total t

UNION ALL

SELECT
  'Last 24h' AS time_window,
  l.drug_class,
  ROUND(SAFE_DIVIDE(l.cnt, t.total) * 100, 2) AS percentage
FROM
  last_24h_counts l
CROSS JOIN
  last_24h_total t

ORDER BY
  time_window,
  drug_class;