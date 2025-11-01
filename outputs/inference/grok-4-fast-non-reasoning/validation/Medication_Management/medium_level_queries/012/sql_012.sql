WITH cohort AS (
  -- Base cohort: women 50-60, inpatient admissions >=72h, non-expired
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) >= 3
    AND a.hospital_expire_flag = 0
    AND a.hadm_id IS NOT NULL  -- Ensure valid admissions
),

diabetes AS (
  -- Type 2 diabetes (ICD-10 E11.*)
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = 10
    AND di.icd_code LIKE 'E11%'
),

heart_failure AS (
  -- Heart failure (ICD-10 I50.*)
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = 10
    AND di.icd_code LIKE 'I50%'
),

qualified_cohort AS (
  -- Intersect conditions
  SELECT c.*
  FROM cohort c
  INNER JOIN diabetes d ON c.hadm_id = d.hadm_id
  INNER JOIN heart_failure hf ON c.hadm_id = hf.hadm_id
),

glp1_pharmacy AS (
  -- GLP-1 from pharmacy orders (hospital-wide)
  SELECT 
    ph.subject_id,
    ph.hadm_id,
    ph.starttime,
    ph.stoptime,
    -- Flag common GLP-1 medications (case-insensitive partial match)
    CASE 
      WHEN LOWER(ph.medication) LIKE '%semaglutide%' 
        OR LOWER(ph.medication) LIKE '%liraglutide%' 
        OR LOWER(ph.medication) LIKE '%dulaglutide%' 
        OR LOWER(ph.medication) LIKE '%exenatide%' 
        OR LOWER(ph.medication) LIKE '%albiglutide%' 
        OR LOWER(ph.medication) LIKE '%lixisenatide%' 
        OR LOWER(ph.medication) LIKE '%tirzepatide%'  -- Dual GLP-1/GIP, often grouped
      THEN 1 ELSE 0 
    END AS is_glp1
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
  WHERE ph.starttime IS NOT NULL
    AND ph.medication IS NOT NULL
),

glp1_input AS (
  -- GLP-1 from ICU inputs (supplemental; match on itemid or label if available)
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.starttime,
    ie.endtime,
    -- For inputs, use itemid lookup in d_items for GLP-1 (limited; fallback to amount >0)
    1 AS is_glp1  -- Placeholder: in practice, filter itemid for known GLP-1 (e.g., 225798 for semaglutide if coded)
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  WHERE ie.amount > 0
    AND (ie.itemid = 225798  -- Known semaglutide itemid
         OR LOWER(di.label) LIKE '%semaglutide%' 
         OR LOWER(di.label) LIKE '%liraglutide%' 
         OR LOWER(di.label) LIKE '%dulaglutide%' 
         OR LOWER(di.label) LIKE '%exenatide%')
  -- Note: GLP-1s are mostly non-ICU; this CTE may return few rows
),

all_glp1 AS (
  -- Union pharmacy and input events (dedup by starttime ~1min tolerance if needed)
  SELECT subject_id, hadm_id, starttime, stoptime, is_glp1 FROM glp1_pharmacy WHERE is_glp1 = 1
  UNION ALL
  SELECT subject_id, hadm_id, starttime, endtime AS stoptime, is_glp1 FROM glp1_input WHERE is_glp1 = 1
),

metrics AS (
  SELECT 
    qc.hadm_id,
    -- First 12h initiation: any GLP-1 start within 12h of admit
    MAX(CASE 
      WHEN ag.starttime >= qc.admittime 
        AND TIMESTAMP_DIFF(ag.starttime, qc.admittime, HOUR) <= 12 
      THEN 1 ELSE 0 
    END) AS initiation_12h,
    -- Final 72h prevalence: any active GLP-1 at 72h (start <=72h and stop >72h or null)
    MAX(CASE 
      WHEN ag.starttime <= TIMESTAMP_ADD(qc.admittime, INTERVAL 72 HOUR)
        AND (ag.stoptime > TIMESTAMP_ADD(qc.admittime, INTERVAL 72 HOUR) OR ag.stoptime IS NULL)
      THEN 1 ELSE 0 
    END) AS prevalence_72h
  FROM qualified_cohort qc
  LEFT JOIN all_glp1 ag 
    ON qc.subject_id = ag.subject_id 
    AND qc.hadm_id = ag.hadm_id
    AND ag.starttime >= qc.admittime  -- Only post-admit events
  GROUP BY qc.hadm_id, qc.admittime
)

SELECT 
  -- Aggregates
  ROUND(AVG(initiation_12h) * 100, 2) AS first_12h_initiation_pct,
  ROUND(AVG(prevalence_72h) * 100, 2) AS final_72h_prevalence_pct,
  ROUND(AVG(prevalence_72h - initiation_12h) * 100, 2) AS net_percentage_point_change
FROM metrics;