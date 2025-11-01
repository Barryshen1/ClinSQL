with `STDDEV(hospital_expire_flag;` — this has two problems:
  1. The opening parenthesis for `STDDEV` is not closed.
  2. There is a stray semicolon inside the `SELECT` list, which is invalid syntax.
- Fix: Correct the line to `STDDEV(hospital_expire_flag) AS sd,` and ensure the query ends with a proper semicolon only after the entire statement.
- Additionally, in the `vital_itemids` CTE, there is a semicolon (`;`) at the end of the `SELECT` statement inside the CTE. In BigQuery, semicolons are not allowed within CTEs or subqueries — they must only appear at the end of the entire query.
- Fix: Remove the semicolon inside the `vital_itemids` CTE.
- All other parts of the query are syntactically valid and logically aligned with the clinical question.

Key changes:
1. Remove the non-SQL text `respiratory failure.` before the `WITH` clause.
2. Remove the semicolon inside the `vital_itemids` CTE.
3. Fix the unclosed `STDDEV` function and stray semicolon in the 'Mortality Rate' block.
4. Ensure the final semicolon is placed only at the end of the full query.

sql
WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
    AND anchor_age >= 40 AND anchor_age <= 50
),

respiratory_failure_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE LOWER(long_title) LIKE '%respiratory failure%'
    AND icd_version = 10
),

patients_with_rf AS (
  SELECT DISTINCT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN respiratory_failure_codes rf ON di.icd_code = rf.icd_code AND di.icd_version = 10
  INNER JOIN patients_filtered pf ON di.subject_id = pf.subject_id
),

first_icu_stay AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu`.icustays icu
  INNER JOIN patients_with_rf rf ON icu.subject_id = rf.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a 
    ON icu.subject_id = a.subject_id AND icu.hadm_id = a.hadm_id
),

cohort AS (
  SELECT *
  FROM first_icu_stay
  WHERE rn = 1
),

vital_itemids AS (
  SELECT itemid, 
    CASE 
      WHEN LOWER(label) LIKE '%heart rate%' THEN 'HR'
      WHEN LOWER(label) LIKE '%mean%blood%pressure%' THEN 'MAP'
      ELSE NULL 
    END AS vital_type
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE linksto = 'chartevents'
),

vitals_first_48h AS (
  SELECT 
    c.subject_id,
    c.stay_id,
    ce.charttime,
    vi.vital_type,
    ce.valuenum
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce 
    ON c.stay_id = ce.stay_id
  INNER JOIN vital_itemids vi 
    ON ce.itemid = vi.itemid
  WHERE ce.charttime >= c.intime 
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),

abnormal_vitals AS (
  SELECT 
    subject_id,
    SUM(CASE WHEN vital_type = 'MAP' AND valuenum < 65 THEN 1 ELSE 0 END) AS map_low_count,
    SUM(CASE WHEN vital_type = 'HR' AND valuenum > 100 THEN 1 ELSE 0 END) AS hr_high_count,
    COUNT(CASE WHEN vital_type = 'MAP' THEN 1 END) AS map_total,
    COUNT(CASE WHEN vital_type = 'HR' THEN 1 END) AS hr_total,
    COUNT(*) AS total_vitals
  FROM vitals_first_48h
  GROUP BY subject_id
),

patient_summary AS (
  SELECT 
    c.subject_id,
    COALESCE(av.map_low_count, 0) AS map_low_count,
    COALESCE(av.hr_high_count, 0) AS hr_high_count,
    COALESCE(av.map_total, 0) AS map_total,
    COALESCE(av.hr_total, 0) AS hr_total,
    COALESCE(av.total_vitals, 0) AS total_vitals,
    c.icu_los,
    c.hospital_expire_flag,
    -- Instability Index: proportion of abnormal vitals (MAP<65 or HR>100)
    SAFE_DIVIDE(
      (COALESCE(av.map_low_count, 0) + COALESCE(av.hr_high_count, 0)),
      COALESCE(av.total_vitals, NULL)
    ) AS instability_index,
    -- Hypotensive burden: % of MAP < 65
    SAFE_DIVIDE(COALESCE(av.map_low_count, 0), COALESCE(av.map_total, NULL)) AS hypotensive_burden,
    -- Tachycardic burden: % of HR > 100
    SAFE_DIVIDE(COALESCE(av.hr_high_count, 0), COALESCE(av.hr_total, NULL)) AS tachycardic_burden
  FROM cohort c
  LEFT JOIN abnormal_vitals av ON c.subject_id = av.subject_id
),

stats AS (
  SELECT
    'Vital Instability Index' AS measure,
    AVG(instability_index) AS mean,
    STDDEV(instability_index) AS sd,
    PERCENTILE_CONT(instability_index, 0.25) OVER() AS p25,
    PERCENTILE_CONT(instability_index, 0.50) OVER() AS p50,
    PERCENTILE_CONT(instability_index, 0.75) OVER() AS p75,
    PERCENTILE_CONT(instability_index, 0.95) OVER() AS p95
  FROM patient_summary
  WHERE instability_index IS NOT NULL

  UNION ALL

  SELECT
    'Hypotensive Burden' AS measure,
    AVG(hypotensive_burden) AS mean,
    STDDEV(hypotensive_burden) AS sd,
    PERCENTILE_CONT(hypotensive_burden, 0.25) OVER() AS p25,
    PERCENTILE_CONT(hypotensive_burden, 0.50) OVER() AS p50,
    PERCENTILE_CONT(hypotensive_burden, 0.75) OVER() AS p75,
    PERCENTILE_CONT(hypotensive_burden, 0.95) OVER() AS p95
  FROM patient_summary
  WHERE hypotensive_burden IS NOT NULL

  UNION ALL

  SELECT
    'Tachycardic Burden' AS measure,
    AVG(tachycardic_burden) AS mean,
    STDDEV(tachycardic_burden) AS sd,
    PERCENTILE_CONT(tachycardic_burden, 0.25) OVER() AS p25,
    PERCENTILE_CONT(tachycardic_burden, 0.50) OVER() AS p50,
    PERCENTILE_CONT(tachycardic_burden, 0.75) OVER() AS p75,
    PERCENTILE_CONT(tachycardic_burden, 0.95) OVER() AS p95
  FROM patient_summary
  WHERE tachycardic_burden IS NOT NULL

  UNION ALL

  SELECT
    'ICU LOS' AS measure,
    AVG(icu_los) AS mean,
    STDDEV(icu_los) AS sd,
    PERCENTILE_CONT(icu_los, 0.25) OVER() AS p25,
    PERCENTILE_CONT(icu_los, 0.50) OVER() AS p50,
    PERCENTILE_CONT(icu_los, 0.75) OVER();