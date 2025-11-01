WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    p.gender, 
    p.anchor_age, 
    p.anchor_year, 
    p.dod,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 59 AND 69
),

pe_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '4151%') OR  -- ICD-9 PE
    (icd_version = 10 AND icd_code LIKE 'I26%')     -- ICD-10 PE
),

comorbidities AS (
  SELECT 
    hadm_id, 
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num > 1   -- Secondary diagnoses only
  GROUP BY hadm_id
),

comorbidity_threshold AS (
  SELECT 
    APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(75)] AS p75_count
  FROM comorbidities
),

cohort_with_comorbidities AS (
  SELECT 
    c.*, 
    COALESCE(co.comorbidity_count, 0) AS comorbidity_count,   -- Default to 0 if no comorbidities
    (COALESCE(co.comorbidity_count, 0) >= (SELECT p75_count FROM comorbidity_threshold)) AS high_comorbidity_flag
  FROM cohort c
  LEFT JOIN comorbidities co
    ON c.hadm_id = co.hadm_id
),

case_group AS (
  SELECT *
  FROM cohort_with_comorbidities
  WHERE hadm_id IN (SELECT hadm_id FROM pe_admissions)
    AND high_comorbidity_flag
),

control_group AS (
  SELECT *
  FROM cohort_with_comorbidities
  WHERE hadm_id NOT IN (SELECT hadm_id FROM pe_admissions)
),

complications AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN (icd_version = 9 AND (icd_code BETWEEN '390' AND '459' OR icd_code BETWEEN '7850' AND '7853' OR icd_code BETWEEN '7855' AND '7859'))
               OR (icd_version = 10 AND icd_code LIKE 'I%') 
          THEN 1 ELSE 0 
        END) AS cardio_comp,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code BETWEEN '320' AND '359') 
               OR (icd_version = 10 AND icd_code LIKE 'G%') 
          THEN 1 ELSE 0 
        END) AS neuro_comp
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num > 1  -- Secondary diagnoses only
  GROUP BY hadm_id
),

mortality AS (
  SELECT 
    hadm_id,
    CASE WHEN DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 30 THEN 1 ELSE 0 END AS mortality_30d
  FROM cohort
  WHERE dod IS NOT NULL
),

case_with_outcomes AS (
  SELECT 
    c.hadm_id,
    c.comorbidity_count,
    c.hospital_expire_flag,  -- Added for survivor LOS filter
    COALESCE(m.mortality_30d, 0) AS mortality_30d,
    COALESCE(cmp.cardio_comp, 0) AS cardio_comp,
    COALESCE(cmp.neuro_comp, 0) AS neuro_comp,
    c.los
  FROM case_group c
  LEFT JOIN mortality m ON c.hadm_id = m.hadm_id
  LEFT JOIN complications cmp ON c.hadm_id = cmp.hadm_id
  -- Removed survivor filter (was: WHERE c.hospital_expire_flag=0)
),

control_with_outcomes AS (
  SELECT 
    c.hadm_id,
    c.comorbidity_count,
    c.hospital_expire_flag,  -- Added for survivor LOS filter
    COALESCE(m.mortality_30d, 0) AS mortality_30d,
    COALESCE(cmp.cardio_comp, 0) AS cardio_comp,
    COALESCE(cmp.neuro_comp, 0) AS neuro_comp,
    c.los
  FROM control_group c
  LEFT JOIN mortality m ON c.hadm_id = m.hadm_id
  LEFT JOIN complications cmp ON c.hadm_id = cmp.hadm_id
  -- Removed survivor filter (was: WHERE c.hospital_expire_flag=0)
),

control_scores AS (
  SELECT comorbidity_count
  FROM control_with_outcomes
),

case_percentiles AS (
  SELECT 
    c.hadm_id,
    c.comorbidity_count,
    -- Compute percentile within control group distribution (fixed ambiguity)
    (SELECT SAFE_DIVIDE(COUNT(*) * 100, (SELECT COUNT(*) FROM control_scores))
     FROM control_scores AS cs  -- Added alias
     WHERE cs.comorbidity_count <= c.comorbidity_count  -- Qualified column
    ) AS comorbidity_percentile
  FROM case_with_outcomes c
)

-- Final results: Case group metrics
SELECT 
  'Case Group' AS cohort,
  COUNT(*) AS n_patients,
  AVG(comorbidity_count) AS mean_comorbidity_count,
  AVG(mortality_30d) * 100 AS mortality_30d_percent,
  AVG(cardio_comp) * 100 AS cardio_comp_percent,
  AVG(neuro_comp) * 100 AS neuro_comp_percent,
  AVG(CASE WHEN hospital_expire_flag = 0 THEN los END) AS mean_survivor_los_days,  -- Conditional on survivors
  AVG(comorbidity_percentile) AS mean_comorbidity_percentile_vs_controls
FROM case_with_outcomes
LEFT JOIN case_percentiles USING (hadm_id)

UNION ALL

-- Control group metrics (for comparison)
SELECT 
  'Control Group' AS cohort,
  COUNT(*) AS n_patients,
  AVG(comorbidity_count) AS mean_comorbidity_count,
  AVG(mortality_30d) * 100 AS mortality_30d_percent,
  AVG(cardio_comp) * 100 AS cardio_comp_percent,
  AVG(neuro_comp) * 100 AS neuro_comp_percent,
  AVG(CASE WHEN hospital_expire_flag = 0 THEN los END) AS mean_survivor_los_days,  -- Conditional on survivors
  NULL AS mean_comorbidity_percentile_vs_controls  -- N/A
FROM control_with_outcomes;