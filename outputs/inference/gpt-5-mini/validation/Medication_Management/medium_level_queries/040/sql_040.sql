WITH cohort AS (
  -- male patients age 36-46 with both diabetes and heart failure diagnoses on the admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    -- has diabetes diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    -- has heart failure diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
), 
-- collect medication records from multiple sources with a normalized name and timestamp
med_orders AS (
  -- prescriptions (hospital)
  SELECT
    hadm_id,
    TIMESTAMP(starttime) AS time,
    LOWER(COALESCE(drug, '')) AS name,
    'prescription' AS src
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE starttime IS NOT NULL

  UNION ALL

  -- hospital pharmacy dispensing / orders
  SELECT
    hadm_id,
    TIMESTAMP(starttime) AS time,
    LOWER(COALESCE(medication, '')) AS name,
    'pharmacy' AS src
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE starttime IS NOT NULL

  UNION ALL

  -- ICU inputevents (use d_items.label for name)
  SELECT
    ie.hadm_id,
    TIMESTAMP(ie.starttime) AS time,
    LOWER(COALESCE(di.label, '')) AS name,
    'inputevents' AS src
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE ie.starttime IS NOT NULL
),

-- map medication names to drug classes of interest; each row is one hadm_id x med_class x time
med_class_matches AS (
  -- Antidiabetic (any) - broad patterns
  SELECT DISTINCT m.hadm_id, 'Antidiabetic (any)' AS med_class, m.time
  FROM med_orders m
  WHERE (
    m.name LIKE '%insulin%' OR
    m.name LIKE '%metformin%' OR
    m.name LIKE '%glipizide%' OR
    m.name LIKE '%glyburide%' OR
    m.name LIKE '%glimepiride%' OR
    m.name LIKE '%sitagliptin%' OR
    m.name LIKE '%saxagliptin%' OR
    m.name LIKE '%linagliptin%' OR
    m.name LIKE '%gliptin%' OR
    m.name LIKE '%flozin%' OR          -- SGLT2 class (dapagliflozin, empagliflozin, etc)
    m.name LIKE '%pioglitazone%' OR
    m.name LIKE '%rosiglitazone%' OR
    m.name LIKE '%liraglutide%' OR
    m.name LIKE '%exenatide%' OR
    m.name LIKE '%semaglutide%' OR
    m.name LIKE '%sulfonyl%' 
  )

  UNION DISTINCT

  -- SGLT2 inhibitors (separate class if you want finer granularity)
  SELECT DISTINCT m.hadm_id, 'SGLT2 inhibitor' AS med_class, m.time
  FROM med_orders m
  WHERE m.name LIKE '%flozin%'

  UNION DISTINCT

  -- ACEI / ARB / ARNI grouped
  SELECT DISTINCT m.hadm_id, 'ACEI/ARB/ARNI' AS med_class, m.time
  FROM med_orders m
  WHERE (
    m.name LIKE '%lisinopril%' OR
    m.name LIKE '%enalapril%' OR
    m.name LIKE '%ramipril%' OR
    m.name LIKE '%benazepril%' OR
    m.name LIKE '%quinapril%' OR
    m.name LIKE '%captopril%' OR
    m.name LIKE '%losartan%' OR
    m.name LIKE '%valsartan%' OR
    m.name LIKE '%candesartan%' OR
    m.name LIKE '%sacubitril%' OR
    m.name LIKE '%sacubitril%' OR
    m.name LIKE '%valsartan%'  -- sacubitril/valsartan handled via sacubitril or valsartan text
  )

  UNION DISTINCT

  -- Beta-blockers
  SELECT DISTINCT m.hadm_id, 'Beta-blocker' AS med_class, m.time
  FROM med_orders m
  WHERE (
    m.name LIKE '%metoprolol%' OR
    m.name LIKE '%carvedilol%' OR
    m.name LIKE '%bisoprolol%' OR
    m.name LIKE '%propranolol%' OR
    m.name LIKE '%atenolol%' OR
    m.name LIKE '%nebivolol%'
  )

  UNION DISTINCT

  -- Mineralocorticoid receptor antagonists (MRA)
  SELECT DISTINCT m.hadm_id, 'MRA (spironolactone/eplerenone)' AS med_class, m.time
  FROM med_orders m
  WHERE (
    m.name LIKE '%spironolactone%' OR
    m.name LIKE '%eplerenone%'
  )

  UNION DISTINCT

  -- Loop diuretics
  SELECT DISTINCT m.hadm_id, 'Loop diuretic' AS med_class, m.time
  FROM med_orders m
  WHERE (
    m.name LIKE '%furosemide%' OR
    m.name LIKE '%bumetanide%' OR
    m.name LIKE '%torsemide%'
  )

  UNION DISTINCT

  -- Any cardiac (any of the above cardiac classes)
  SELECT DISTINCT m.hadm_id, 'Any cardiac' AS med_class, m.time
  FROM med_orders m
  WHERE (
    LOWER(m.name) LIKE '%metoprolol%' OR LOWER(m.name) LIKE '%carvedilol%' OR LOWER(m.name) LIKE '%bisoprolol%' OR
    LOWER(m.name) LIKE '%propranolol%' OR LOWER(m.name) LIKE '%atenolol%' OR LOWER(m.name) LIKE '%nebivolol%' OR
    LOWER(m.name) LIKE '%lisinopril%' OR LOWER(m.name) LIKE '%enalapril%' OR LOWER(m.name) LIKE '%ramipril%' OR
    LOWER(m.name) LIKE '%benazepril%' OR LOWER(m.name) LIKE '%quinapril%' OR LOWER(m.name) LIKE '%captopril%' OR
    LOWER(m.name) LIKE '%losartan%' OR LOWER(m.name) LIKE '%valsartan%' OR LOWER(m.name) LIKE '%candesartan%' OR
    LOWER(m.name) LIKE '%sacubitril%' OR
    LOWER(m.name) LIKE '%spironolactone%' OR LOWER(m.name) LIKE '%eplerenone%' OR
    LOWER(m.name) LIKE '%furosemide%' OR LOWER(m.name) LIKE '%bumetanide%' OR LOWER(m.name) LIKE '%torsemide%'
  )
),

-- attach admission times and compute window membership
med_windows AS (
  SELECT
    cm.hadm_id,
    cm.med_class,
    cm.time,
    c.admittime,
    c.dischtime,
    -- flags for windows
    TIMESTAMP(cm.time) BETWEEN TIMESTAMP(c.admittime) AND TIMESTAMP_ADD(TIMESTAMP(c.admittime), INTERVAL 48 HOUR) AS in_first_48h,
    TIMESTAMP(cm.time) BETWEEN TIMESTAMP_SUB(TIMESTAMP(c.dischtime), INTERVAL 12 HOUR) AND TIMESTAMP(c.dischtime) AS in_last_12h
  FROM med_class_matches cm
  JOIN cohort c USING (hadm_id)
  WHERE cm.time IS NOT NULL
),

-- For each hadm_id and med_class, determine whether there is at least one exposure in each window
per_admission_class AS (
  SELECT
    hadm_id,
    med_class,
    MAX(CAST(in_first_48h AS INT64)) > 0 AS any_in_first_48h,
    MAX(CAST(in_last_12h AS INT64)) > 0 AS any_in_last_12h
  FROM med_windows
  GROUP BY hadm_id, med_class
),

-- totals
cohort_counts AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_admissions
  FROM cohort
)

SELECT
  pac.med_class,
  COUNTIF(pac.any_in_first_48h) AS n_first48,
  ROUND(100.0 * COUNTIF(pac.any_in_first_48h) / cc.total_admissions, 2) AS pct_first48,
  COUNTIF(pac.any_in_last_12h) AS n_last12,
  ROUND(100.0 * COUNTIF(pac.any_in_last_12h) / cc.total_admissions, 2) AS pct_last12,
  ROUND(100.0 * (COUNTIF(pac.any_in_first_48h) - COUNTIF(pac.any_in_last_12h)) / cc.total_admissions, 2) AS abs_diff_pp
FROM per_admission_class pac
CROSS JOIN cohort_counts cc
GROUP BY pac.med_class, cc.total_admissions
ORDER BY
  -- put antidiabetic and then cardiac classes first (optional)
  CASE
    WHEN pac.med_class = 'Antidiabetic (any)' THEN 0
    WHEN pac.med_class = 'SGLT2 inhibitor' THEN 1
    WHEN pac.med_class = 'Any cardiac' THEN 2
    WHEN pac.med_class = 'ACEI/ARB/ARNI' THEN 3
    WHEN pac.med_class = 'Beta-blocker' THEN 4
    WHEN pac.med_class = 'MRA (spironolactone/eplerenone)' THEN 5
    WHEN pac.med_class = 'Loop diuretic' THEN 6
    ELSE 10
  END,
  pac.med_class;