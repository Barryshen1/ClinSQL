WITH dx AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabet%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%heart fail%' OR LOWER(dd.long_title) LIKE '%congestive heart%' THEN 1 ELSE 0 END) AS has_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  GROUP BY
    d.hadm_id
),
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    icu.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    icu.hadm_id = a.hadm_id
  JOIN
    dx
  ON
    icu.hadm_id = dx.hadm_id
  WHERE
    -- female patients aged 37-47 inclusive
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    -- ICU stay length at least 144 hours (los is in days)
    AND icu.los * 24 >= 144
    -- must have both diabetes and heart failure diagnoses on the admission
    AND dx.has_diabetes = 1
    AND dx.has_hf = 1
),
-- Map prescriptions to medication classes (text matching on prescriptions.drug)
pres AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    p.starttime,
    p.stoptime,
    p.drug,
    -- medication class mapping by common drug name fragments
    CASE
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(p.drug, '')), r'\b(insulin|metformin|glyburide|glipizide|glimepiride|pioglitazone|rosiglitazone|empagliflozin|dapagliflozin|canagliflozin|liraglutide|semaglutide|exenatide|sitagliptin|linagliptin|alogliptin|vildagliptin|glimepiride|chlorpropamide)\b') THEN 'antidiabetic'
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(p.drug, '')), r'\b(metoprolol|atenolol|bisoprolol|propranolol|carvedilol|nebivolol|nadolol|timolol|esmolol|sotalol)\b') THEN 'beta_blocker'
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(p.drug, '')), r'\b(lisinopril|enalapril|ramipril|benazepril|quinapril|perindopril|fosinopril|losartan|valsartan|irbesartan|candesartan|olmesartan|sacubitril|entresto|sacubitril\s*\/?\s*valsartan)\b') THEN 'acei_arb_arni'
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(p.drug, '')), r'\b(furosemide|lasix|bumetanide|torsemide)\b') THEN 'loop_diuretic'
      ELSE NULL
    END AS med_class
  FROM
    cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  ON
    c.hadm_id = p.hadm_id
    AND c.subject_id = p.subject_id
),
-- For each prescription row compute whether it overlaps the first and/or final 72h windows.
pres_overlap AS (
  SELECT
    stay_id,
    hadm_id,
    med_class,
    -- define first and final window endpoints
    intime AS first_start,
    TIMESTAMP_ADD(intime, INTERVAL 72 HOUR) AS first_end,
    TIMESTAMP_SUB(outtime, INTERVAL 72 HOUR) AS final_start,
    outtime AS final_end,
    -- prescription interval
    starttime,
    stoptime,
    -- overlap booleans
    CASE
      WHEN med_class IS NOT NULL
       AND starttime < TIMESTAMP_ADD(intime, INTERVAL 72 HOUR)
       AND (stoptime IS NULL OR stoptime > intime)
      THEN 1 ELSE 0 END AS overlap_first,
    CASE
      WHEN med_class IS NOT NULL
       AND starttime < outtime
       AND (stoptime IS NULL OR stoptime > TIMESTAMP_SUB(outtime, INTERVAL 72 HOUR))
      THEN 1 ELSE 0 END AS overlap_final
  FROM
    pres
),
-- For each stay_id and med_class reduce to one row indicating whether any prescription overlaps first/final window
stay_med_flags AS (
  SELECT
    stay_id,
    med_class,
    MAX(overlap_first) AS on_first,
    MAX(overlap_final) AS on_final
  FROM
    pres_overlap
  GROUP BY
    stay_id,
    med_class
),
-- It is possible some stays have no prescriptions matching any class -> include those with explicit zeros for each class
distinct_stays AS (
  SELECT DISTINCT stay_id FROM cohort
),
classes AS (
  SELECT 'antidiabetic' AS med_class UNION ALL
  SELECT 'beta_blocker' UNION ALL
  SELECT 'acei_arb_arni' UNION ALL
  SELECT 'loop_diuretic'
),
-- Ensure every (stay, class) pair exists: left join flags to all pairs of stays x classes
stay_class_full AS (
  SELECT
    s.stay_id,
    c.med_class,
    COALESCE(f.on_first, 0) AS on_first,
    COALESCE(f.on_final, 0) AS on_final
  FROM
    distinct_stays s
  CROSS JOIN
    classes c
  LEFT JOIN
    stay_med_flags f
  ON
    s.stay_id = f.stay_id
    AND c.med_class = f.med_class
),
-- Aggregate to compute counts and percentages and continued/initiated/discontinued
agg AS (
  SELECT
    sc.med_class,
    COUNT(DISTINCT sc.stay_id) AS total_stays,
    SUM(sc.on_first) AS first_count,
    SUM(sc.on_final) AS final_count,
    SAFE_DIVIDE(SUM(sc.on_first), COUNT(DISTINCT sc.stay_id)) * 100.0 AS pct_first,
    SAFE_DIVIDE(SUM(sc.on_final), COUNT(DISTINCT sc.stay_id)) * 100.0 AS pct_final,
    SUM(CASE WHEN sc.on_first = 1 AND sc.on_final = 1 THEN 1 ELSE 0 END) AS continued_count,
    SUM(CASE WHEN sc.on_first = 0 AND sc.on_final = 1 THEN 1 ELSE 0 END) AS initiated_count,
    SUM(CASE WHEN sc.on_first = 1 AND sc.on_final = 0 THEN 1 ELSE 0 END) AS discontinued_count
  FROM
    stay_class_full sc
  GROUP BY
    sc.med_class
)
SELECT
  med_class,
  total_stays,
  first_count,
  ROUND(pct_first, 2) AS pct_first,
  final_count,
  ROUND(pct_final, 2) AS pct_final,
  continued_count,
  initiated_count,
  discontinued_count
FROM
  agg
ORDER BY
  med_class;