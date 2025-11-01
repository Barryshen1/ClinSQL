WITH patient_cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND (a.dischtime - a.admittime) >= INTERVAL '12' HOUR -- at least 12h stay
),
diabetes_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE LOWER(long_title) LIKE '%diabetes%'
    AND icd_version IN (9, 10)
),
hf_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (
    LOWER(long_title) LIKE '%heart failure%'
    OR LOWER(long_title) LIKE '%cardiomyopathy%'
    OR LOWER(long_title) LIKE '%congestive heart failure%'
    OR LOWER(long_title) LIKE '%systolic dysfunction%'
    OR LOWER(long_title) LIKE '%diastolic dysfunction%'
  )
  AND icd_version IN (9, 10)
),
cohort_with_diagnoses AS (
  SELECT pc.subject_id, pc.hadm_id, pc.admittime, pc.dischtime
  FROM patient_cohort pc
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    WHERE di.hadm_id = pc.hadm_id
      AND di.icd_code IN (SELECT icd_code FROM diabetes_codes)
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    WHERE di.hadm_id = pc.hadm_id
      AND di.icd_code IN (SELECT icd_code FROM hf_codes)
  )
),
drug_administration AS (
  SELECT 
    em.subject_id,
    em.hadm_id,
    em.charttime,
    LOWER(em.medication) AS medication
  FROM `physionet-data.mimiciv_3_1_hosp`.emar em
  WHERE em.hadm_id IN (SELECT hadm_id FROM cohort_with_diagnoses)
    AND em.event_txt = 'Administered' -- only administered doses
),
drug_class AS (
  SELECT 
    da.subject_id,
    da.hadm_id,
    da.charttime,
    CASE
      WHEN LOWER(da.medication) LIKE '%insulin%'
        OR LOWER(da.medication) LIKE '%metformin%'
        OR LOWER(da.medication) LIKE '%glipizide%'
        OR LOWER(da.medication) LIKE '%glyburide%'
        OR LOWER(da.medication) LIKE '%glimepiride%'
        OR LOWER(da.medication) LIKE '%sitagliptin%'
        OR LOWER(da.medication) LIKE '%liraglutide%'
        OR LOWER(da.medication) LIKE '%dulaglutide%'
        OR LOWER(da.medication) LIKE '%semaglutide%'
        OR LOWER(da.medication) LIKE '%exenatide%'
        OR LOWER(da.medication) LIKE '%empagliflozin%'
        OR LOWER(da.medication) LIKE '%dapagliflozin%'
        OR LOWER(da.medication) LIKE '%canagliflozin%'
        THEN 'antidiabetics'
      WHEN LOWER(da.medication) LIKE '%metoprolol%'
        OR LOWER(da.medication) LIKE '%carvedilol%'
        OR LOWER(da.medication) LIKE '%bisoprolol%'
        OR LOWER(da.medication) LIKE '%atenolol%'
        OR LOWER(da.medication) LIKE '%nadolol%'
        OR LOWER(da.medication) LIKE '%propranolol%'
        THEN 'beta_blockers'
      WHEN LOWER(da.medication) LIKE '%lisinopril%'
        OR LOWER(da.medication) LIKE '%enalapril%'
        OR LOWER(da.medication) LIKE '%ramipril%'
        OR LOWER(da.medication) LIKE '%captopril%'
        OR LOWER(da.medication) LIKE '%benazepril%'
        OR LOWER(da.medication) LIKE '%perindopril%'
        OR LOWER(da.medication) LIKE '%quinapril%'
        OR LOWER(da.medication) LIKE '%trandolapril%'
        OR LOWER(da.medication) LIKE '%fosinopril%'
        OR LOWER(da.medication) LIKE '%losartan%'
        OR LOWER(da.medication) LIKE '%valsartan%'
        OR LOWER(da.medication) LIKE '%irbesartan%'
        OR LOWER(da.medication) LIKE '%candesartan%'
        OR LOWER(da.medication) LIKE '%olmesartan%'
        OR LOWER(da.medication) LIKE '%azilsartan%'
        OR LOWER(da.medication) LIKE '%sacubitril%'
        OR LOWER(da.medication) LIKE '%entresto%'
        OR LOWER(da.medication) LIKE '%sacubitril/valsartan%'
        THEN 'acei_arb_arni'
      WHEN LOWER(da.medication) LIKE '%furosemide%'
        OR LOWER(da.medication) LIKE '%bumetanide%'
        OR LOWER(da.medication) LIKE '%torsemide%'
        OR LOWER(da.medication) LIKE '%ethacrynic%'
        THEN 'loop_diuretics'
      ELSE NULL
    END AS drug_class
  FROM drug_administration da
  WHERE da.medication IS NOT NULL
),
first_admin_class AS (
  SELECT 
    subject_id,
    hadm_id,
    drug_class,
    MIN(charttime) AS first_admin_time
  FROM drug_class
  WHERE drug_class IS NOT NULL
  GROUP BY subject_id, hadm_id, drug_class
),
initiation_timing AS (
  SELECT 
    fac.subject_id,
    fac.hadm_id,
    fac.drug_class,
    CASE 
      WHEN fac.first_admin_time <= (c.admittime + INTERVAL '48' HOUR)
        THEN 1 ELSE 0 END AS initiated_first_48h,
    CASE 
      WHEN fac.first_admin_time >= (c.dischtime - INTERVAL '12' HOUR)
        AND fac.first_admin_time <= c.dischtime
        THEN 1 ELSE 0 END AS initiated_last_12h
  FROM first_admin_class fac
  JOIN cohort_with_diagnoses c
    ON fac.subject_id = c.subject_id AND fac.hadm_id = c.hadm_id
),
summary AS (
  SELECT 
    drug_class,
    AVG(initiated_first_48h) * 100 AS pct_initiated_first_48h,
    AVG(initiated_last_12h) * 100 AS pct_initiated_last_12h
  FROM initiation_timing
  GROUP BY drug_class
)
SELECT 
  drug_class,
  ROUND(pct_initiated_first_48h, 2) AS pct_initiated_first_48h,
  ROUND(pct_initiated_last_12h, 2) AS pct_initiated_last_12h,
  ROUND(pct_initiated_last_12h - pct_initiated_first_48h, 2) AS net_change
FROM summary
ORDER BY drug_class;