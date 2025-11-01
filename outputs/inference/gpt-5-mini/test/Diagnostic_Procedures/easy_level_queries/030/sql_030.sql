WITH female_adms AS (
  SELECT
    a.hadm_id,
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
),

-- Echocardiography-like entries from hospital HCPCS/CPT events
echo_procs_hcpcs AS (
  SELECT
    hadm_id,
    CONCAT('hcpcs:', COALESCE(hcpcs_cd, '')) AS proc_code
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE LOWER(COALESCE(short_description, '')) LIKE '%echo%'
     OR LOWER(COALESCE(short_description, '')) LIKE '%echocardi%'
     OR LOWER(COALESCE(short_description, '')) LIKE '%echocardiogram%'
     OR LOWER(COALESCE(short_description, '')) LIKE '%transesophageal%'
     OR LOWER(COALESCE(short_description, '')) LIKE '%cardiac ultrasound%'
),

-- Echocardiography-like entries from ICU procedureevents (via d_items labels)
echo_procs_icu AS (
  SELECT
    pe.hadm_id,
    CONCAT('item:', CAST(pe.itemid AS STRING)) AS proc_code
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE LOWER(COALESCE(di.label, '')) LIKE '%echo%'
     OR LOWER(COALESCE(di.label, '')) LIKE '%echocardi%'
     OR LOWER(COALESCE(di.label, '')) LIKE '%echocardiogram%'
     OR LOWER(COALESCE(di.label, '')) LIKE '%transesophageal%'
     OR LOWER(COALESCE(di.label, '')) LIKE '%cardiac ultrasound%'
),

-- Union the procedure identifiers from both sources (distinct)
echo_procs AS (
  SELECT * FROM echo_procs_hcpcs
  UNION DISTINCT
  SELECT * FROM echo_procs_icu
),

-- For each eligible hospitalization, count distinct echocardiography procedure codes
hadm_echo_counts AS (
  SELECT
    fa.hadm_id,
    COUNT(DISTINCT ep.proc_code) AS echo_distinct_count
  FROM female_adms fa
  LEFT JOIN echo_procs ep
    ON fa.hadm_id = ep.hadm_id
  GROUP BY fa.hadm_id
),

-- Metadata: number of hospitalizations considered
meta AS (
  SELECT COUNT(*) AS n
  FROM hadm_echo_counts
),

-- Ordered array of counts (ascending)
agg_arr AS (
  SELECT ARRAY_AGG(echo_distinct_count ORDER BY echo_distinct_count) AS arr
  FROM hadm_echo_counts
)

-- Select the discrete 25th percentile: element at position ceil(0.25 * n)
SELECT
  CASE
    WHEN meta.n = 0 THEN NULL
    ELSE arr[OFFSET(GREATEST(0, CAST(CEIL(0.25 * meta.n) AS INT64) - 1))]
  END AS pct25_distinct_echo_per_hadm,
  meta.n AS n_hospitalizations_considered
FROM agg_arr
CROSS JOIN meta;