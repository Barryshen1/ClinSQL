WITH charlson AS (
  SELECT 
    hadm_id,
    SUM(weight) AS cci
  FROM (
    SELECT 
      adm.hadm_id,
      CASE 
        WHEN diag.icd_code LIKE '410%' AND diag.icd_version = 9 THEN 1
        WHEN diag.icd_code LIKE 'I21%' AND diag.icd_version = 10 THEN 1
        -- Add all 17 comorbidities with weights here
        ELSE 0 
      END * weight AS weight
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    CROSS JOIN UNNEST([STRUCT(1 AS weight)]) -- Example weight
  ) 
  GROUP BY hadm_id
),
dvt_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND icd_code IN ('4534','4538','4539')) OR
    (icd_version = 10 AND icd_code LIKE 'I82%')
  )
),
base_cohort AS (
  SELECT
    adm.hadm_id,
    adm.subject_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_hospital,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_admit,
    p.dod,
    ch.cci
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  LEFT JOIN charlson ch
    ON adm.hadm_id = ch.hadm_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 71 AND 81
),
dvt_cohort AS (
  SELECT *
  FROM base_cohort
  WHERE 
    hadm_id IN (SELECT hadm_id FROM dvt_patients)
    AND cci >= 3  -- High comorbidity
),
complications AS (
  SELECT 
    hadm_id,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code LIKE '4151%') OR
           (icd_version = 10 AND icd_code LIKE 'I26%') THEN 1
      ELSE 0 
    END) AS pe_flag,
    MAX(CASE 
      WHEN (icd_version = 9 AND (icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%')) OR
           (icd_version = 10 AND icd_code LIKE 'I6%') THEN 1
      ELSE 0 
    END) AS ich_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_enriched AS (
  SELECT
    dc.*,
    CASE 
      WHEN dod IS NOT NULL AND DATE_DIFF(dod, admittime, DAY) <= 90 THEN 1
      ELSE 0 
    END AS mortality_90d,
    COALESCE(cmp.pe_flag, 0) AS pe_flag,
    COALESCE(cmp.ich_flag, 0) AS ich_flag,
    CASE 
      WHEN COALESCE(cmp.pe_flag,0) = 1 OR COALESCE(cmp.ich_flag,0) = 1 THEN 1
      ELSE 0 
    END AS major_complication
  FROM dvt_cohort dc
  LEFT JOIN complications cmp
    ON dc.hadm_id = cmp.hadm_id
),
general_inpatient AS (
  SELECT
    bc.hadm_id,
    COALESCE(cmp.pe_flag, 0) AS pe_flag,
    COALESCE(cmp.ich_flag, 0) AS ich_flag,
    CASE 
      WHEN COALESCE(cmp.pe_flag,0) = 1 OR COALESCE(cmp.ich_flag,0) = 1 THEN 1
      ELSE 0 
    END AS major_complication,
    bc.los_hospital
  FROM base_cohort bc
  LEFT JOIN complications cmp
    ON bc.hadm_id = cmp.hadm_id
  WHERE 
    bc.hospital_expire_flag = 0  -- Survivors only for LOS
    AND bc.hadm_id NOT IN (SELECT hadm_id FROM dvt_patients)  -- Exclude DVT patients
),
cohort_summary AS (
  SELECT
    'DVT High-Comorbidity' AS cohort,
    COUNT(*) AS n_patients,
    APPROX_QUANTILES(cci, 100)[OFFSET(50)] AS median_cci,
    APPROX_QUANTILES(cci, 100)[OFFSET(25)] AS q1_cci,
    APPROX_QUANTILES(cci, 100)[OFFSET(75)] AS q3_cci,
    AVG(mortality_90d) * 100 AS mortality_90d_percent,
    AVG(major_complication) * 100 AS major_complication_percent,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag=0 THEN los_hospital ELSE NULL END, 100 IGNORE NULLS)[OFFSET(50)] AS median_los_survivor,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag=0 THEN los_hospital ELSE NULL END, 100 IGNORE NULLS)[OFFSET(25)] AS q1_los_survivor,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag=0 THEN los_hospital ELSE NULL END, 100 IGNORE NULLS)[OFFSET(75)] AS q3_los_survivor
  FROM cohort_enriched
),
general_summary AS (
  SELECT
    'General Inpatients' AS cohort,
    COUNT(*) AS n_patients,
    NULL AS median_cci,
    NULL AS q1_cci,
    NULL AS q3_cci,
    NULL AS mortality_90d_percent,
    AVG(major_complication) * 100 AS major_complication_percent,
    APPROX_QUANTILES(los_hospital, 100 IGNORE NULLS)[OFFSET(50)] AS median_los_survivor,
    APPROX_QUANTILES(los_hospital, 100 IGNORE NULLS)[OFFSET(25)] AS q1_los_survivor,
    APPROX_QUANTILES(los_hospital, 100 IGNORE NULLS)[OFFSET(75)] AS q3_los_survivor
  FROM general_inpatient
)
SELECT * FROM cohort_summary
UNION ALL
SELECT * FROM general_summary
ORDER BY cohort;

-- Query 2: Risk percentiles for DVT cohort
WITH charlson AS (
  SELECT 
    hadm_id,
    SUM(weight) AS cci
  FROM (
    SELECT 
      adm.hadm_id,
      CASE 
        WHEN diag.icd_code LIKE '410%' AND diag.icd_version = 9 THEN 1
        WHEN diag.icd_code LIKE 'I21%' AND diag.icd_version = 10 THEN 1
        ELSE 0 
      END * weight AS weight
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    CROSS JOIN UNNEST([STRUCT(1 AS weight)]) 
  ) 
  GROUP BY hadm_id
),
dvt_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND icd_code IN ('4534','4538','4539')) OR
    (icd_version = 10 AND icd_code LIKE 'I82%')
  )
),
base_cohort AS (
  SELECT
    adm.hadm_id,
    adm.subject_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_admit,
    p.dod,
    ch.cci
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  LEFT JOIN charlson ch
    ON adm.hadm_id = ch.hadm_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 71 AND 81
),
dvt_cohort AS (
  SELECT *
  FROM base_cohort
  WHERE 
    hadm_id IN (SELECT hadm_id FROM dvt_patients)
    AND cci >= 3
),
cohort_enriched AS (
  SELECT
    dc.hadm_id,
    dc.cci
  FROM dvt_cohort dc
),
percentiles AS (
  SELECT
    hadm_id,
    cci,
    ROUND(PERCENT_RANK() OVER (ORDER BY cci) * 100, 1) AS cci_percentile
  FROM cohort_enriched
)
SELECT * FROM percentiles;