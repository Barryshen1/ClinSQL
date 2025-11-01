WITH hemorrhagic_hadms AS (
  -- mark admissions that contain any hemorrhagic-stroke diagnosis
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dc
    ON d.icd_code = dc.icd_code
   AND d.icd_version = dc.icd_version
  WHERE LOWER(dc.long_title) LIKE '%hemorrhag%' -- catches intracerebral/subarachnoid hemorrhage strings
    AND d.hadm_id IS NOT NULL
),

cohort AS (
  -- female inpatients aged 48-58 (anchor_age used for de-identified ages)
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    CASE WHEN h.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS hemorrhagic_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN hemorrhagic_hadms h
    ON a.hadm_id = h.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.hadm_id IS NOT NULL
),

meds_prescriptions AS (
  -- hospital prescriptions during first 48 hours
  SELECT
    c.hadm_id,
    LOWER(TRIM(presc.drug)) AS med_name
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` presc
    ON c.hadm_id = presc.hadm_id
  WHERE presc.starttime IS NOT NULL
    AND presc.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND LOWER(TRIM(presc.drug)) <> ''
),

meds_inputevents AS (
  -- ICU inputevents during first 48 hours (use d_items.label for text)
  SELECT
    c.hadm_id,
    LOWER(TRIM(d.label)) AS med_name
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON c.hadm_id = ie.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON ie.itemid = d.itemid
  WHERE ie.starttime IS NOT NULL
    AND ie.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND d.label IS NOT NULL
    AND LOWER(TRIM(d.label)) <> ''
),

meds_union AS (
  -- union medication name sources for first 48h, keep distinct med names per hadm
  SELECT DISTINCT hadm_id, med_name FROM meds_prescriptions
  UNION DISTINCT
  SELECT DISTINCT hadm_id, med_name FROM meds_inputevents
),

meds_per_hadm AS (
  -- compute complexity (# distinct meds) and serotonergic_count (distinct serotonergic meds) per hadm
  SELECT
    c.hadm_id,
    c.hemorrhagic_flag,
    c.los_days,
    c.hospital_expire_flag,
    COUNT(m.med_name) AS complexity,
    -- count distinct serotonergic medications by regex matching on med_name substrings
    COUNT(DISTINCT CASE
      WHEN REGEXP_CONTAINS(m.med_name,
        r'fluox|sertral|parox|citalopram|escitalopram|venlaf|dulox|trazod|mirtaz|tramadol|ondansetron|metoclopramide|linezolid|sumatriptan|rizatriptan|zolmitriptan|eletriptan|almotriptan')
      THEN m.med_name ELSE NULL END
    ) AS serotonergic_count
  FROM cohort c
  LEFT JOIN meds_union m ON c.hadm_id = m.hadm_id
  GROUP BY c.hadm_id, c.hemorrhagic_flag, c.los_days, c.hospital_expire_flag
),

quartiles AS (
  -- compute the 75th percentile (3rd quartile) for complexity across the whole cohort
  SELECT
    (approx_quantiles(complexity, 4))[OFFSET(3)] AS q3_threshold
  FROM meds_per_hadm
),

cohort_with_flags AS (
  SELECT
    m.*,
    q.q3_threshold,
    CASE WHEN m.complexity >= q.q3_threshold THEN 1 ELSE 0 END AS top_quartile_flag
  FROM meds_per_hadm m
  CROSS JOIN quartiles q
),

-- Prepare counts per complexity & hemorrhagic_flag so we can compute within-group percentages with a window
complexity_counts AS (
  SELECT
    hemorrhagic_flag,
    complexity,
    COUNT(*) AS n_patients
  FROM cohort_with_flags
  GROUP BY hemorrhagic_flag, complexity
),

complexity_counts_with_pct AS (
  SELECT
    hemorrhagic_flag,
    CAST(complexity AS STRING) AS subgroup,
    n_patients,
    ROUND(100.0 * n_patients / SUM(n_patients) OVER (PARTITION BY hemorrhagic_flag), 2) AS pct_within_group
  FROM complexity_counts
)

-- Final outputs: three sections in one result set
SELECT
  'complexity_distribution' AS analysis,
  CAST(hemorrhagic_flag AS STRING) AS hemorrhagic_flag,
  subgroup,
  n_patients,
  pct_within_group,
  CAST(NULL AS FLOAT64) AS mean_los_days,
  CAST(NULL AS FLOAT64) AS median_los_days,
  CAST(NULL AS FLOAT64) AS mortality_rate
FROM complexity_counts_with_pct

UNION ALL

SELECT
  'serotonergic_>=2_vs_<2' AS analysis,
  CAST(hemorrhagic_flag AS STRING) AS hemorrhagic_flag,
  CASE WHEN serotonergic_count >= 2 THEN 'serotonergic_>=2' ELSE 'serotonergic_<2' END AS subgroup,
  COUNT(*) AS n_patients,
  CAST(NULL AS FLOAT64) AS pct_within_group,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  -- approximate median via approx_quantiles: get 100-quantiles and take the 50th percentile
  (approx_quantiles(los_days, 100))[OFFSET(50)] AS median_los_days,
  ROUND(100.0 * SUM(CAST(hospital_expire_flag AS INT64)) / COUNT(*), 2) AS mortality_rate
FROM cohort_with_flags
GROUP BY hemorrhagic_flag, CASE WHEN serotonergic_count >= 2 THEN 'serotonergic_>=2' ELSE 'serotonergic_<2' END

UNION ALL

SELECT
  'top_complexity_quartile_vs_others' AS analysis,
  CAST(hemorrhagic_flag AS STRING) AS hemorrhagic_flag,
  CASE WHEN top_quartile_flag = 1 THEN 'top_quartile' ELSE 'other_quartiles' END AS subgroup,
  COUNT(*) AS n_patients,
  CAST(NULL AS FLOAT64) AS pct_within_group,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  (approx_quantiles(los_days, 100))[OFFSET(50)] AS median_los_days,
  ROUND(100.0 * SUM(CAST(hospital_expire_flag AS INT64)) / COUNT(*), 2) AS mortality_rate
FROM cohort_with_flags
GROUP BY hemorrhagic_flag, top_quartile_flag

ORDER BY analysis, hemorrhagic_flag, subgroup;