WITH patient_cohort AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 86 AND 96
),
admissions_cohort AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patient_cohort p ON a.subject_id = p.subject_id
),
proc_icd AS (
  SELECT a.hadm_id, COUNT(DISTINCT proc.icd_code) as count_proc_icd
  FROM admissions_cohort a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc ON a.hadm_id = proc.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
  WHERE d_proc.long_title LIKE '%ECMO%' OR d_proc.long_title LIKE '%Mechanical circulatory support%' 
  OR d_proc.long_title LIKE '%LVAD%' OR d_proc.long_title LIKE '%RVAD%' 
  GROUP BY a.hadm_id
),
proc_event AS (
  SELECT a.hadm_id, COUNT(DISTINCT pe.itemid) as count_proc_event
  FROM admissions_cohort a
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON a.hadm_id = pe.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d_i ON pe.itemid = d_i.itemid
  WHERE LOWER(d_i.label) LIKE '%ecmo%' OR LOWER(d_i.label) LIKE '%lvad%' 
  OR LOWER(d_i.label) LIKE '%rvad%' OR LOWER(d_i.label) LIKE '%mechanical circulatory support%'
  GROUP BY a.hadm_id
),
combined_procedures AS (
  SELECT COALESCE(proc_icd.hadm_id, proc_event.hadm_id) AS hadm_id, 
         COALESCE(count_proc_icd, 0) + COALESCE(count_proc_event, 0) as total_procedures
  FROM proc_icd
  FULL OUTER JOIN proc_event ON proc_icd.hadm_id = proc_event.hadm_id
),
iqr_calc AS (
  SELECT 
    APPROX_QUANTILES(total_procedures, 100) AS quantiles
  FROM combined_procedures
)
SELECT 
  quantiles[OFFSET(25)] AS q1,
  quantiles[OFFSET(50)] AS median,
  quantiles[OFFSET(75)] AS q3
FROM iqr_calc;