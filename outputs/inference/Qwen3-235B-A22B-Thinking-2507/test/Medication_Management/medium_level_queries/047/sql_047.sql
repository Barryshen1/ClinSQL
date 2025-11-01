WITH patients_with_age AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE a.dischtime IS NOT NULL
),
diagnoses AS (
  SELECT 
    hadm_id,
    MAX(CASE 
      WHEN icd_version = 9 AND icd_code LIKE '250%' THEN 1
      WHEN icd_version = 10 AND icd_code LIKE 'E08%' THEN 1
      WHEN icd_version = 10 AND icd_code LIKE 'E09%' THEN 1
      WHEN icd_version = 10 AND icd_code LIKE 'E10%' THEN 1
      WHEN icd_version = 10 AND icd_code LIKE 'E11%' THEN 1
      WHEN icd_version = 10 AND icd_code LIKE 'E13%' THEN 1
      ELSE 0 
    END) AS has_diabetes,
    MAX(CASE 
      WHEN icd_version = 9 AND icd_code LIKE '428%' THEN 1
      WHEN icd_version = 10 AND icd_code LIKE 'I50%' THEN 1
      ELSE 0 
    END) AS has_heart_failure
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort AS (
  SELECT 
    pwa.hadm_id,
    pwa.admittime,
    pwa.dischtime
  FROM patients_with_age pwa
  INNER JOIN diagnoses d 
    ON pwa.hadm_id = d.hadm_id
  WHERE 
    pwa.gender = 'M'
    AND pwa.age >= 40 
    AND pwa.age <= 50
    AND d.has_diabetes = 1
    AND d.has_heart_failure = 1
),
medication_orders AS (
  SELECT 
    hadm_id,
    starttime,
    stoptime,
    admittime,
    dischtime,
    med_class,
    first_24h_flag,
    last_24h_flag
  FROM (
    SELECT 
      p.hadm_id,
      p.starttime,
      p.stoptime,
      c.admittime,
      c.dischtime,
      CASE 
        WHEN LOWER(p.drug) LIKE '%insulin%' 
          OR LOWER(p.drug) LIKE '%metformin%' 
          OR LOWER(p.drug) LIKE '%glipizide%' 
          OR LOWER(p.drug) LIKE '%glyburide%' 
          OR LOWER(p.drug) LIKE '%glimepiride%' 
          OR LOWER(p.drug) LIKE '%sitagliptin%' 
          OR LOWER(p.drug) LIKE '%saxagliptin%' 
          OR LOWER(p.drug) LIKE '%linagliptin%' 
          OR LOWER(p.drug) LIKE '%alogliptin%' 
          OR LOWER(p.drug) LIKE '%empagliflozin%' 
          OR LOWER(p.drug) LIKE '%canagliflozin%' 
          OR LOWER(p.drug) LIKE '%dapagliflozin%' 
          OR LOWER(p.drug) LIKE '%ertugliflozin%' 
          OR LOWER(p.drug) LIKE '%liraglutide%' 
          OR LOWER(p.drug) LIKE '%semaglutide%' 
          OR LOWER(p.drug) LIKE '%exenatide%' 
          OR LOWER(p.drug) LIKE '%pioglitazone%' 
          OR LOWER(p.drug) LIKE '%rosiglitazone%' 
          OR LOWER(p.drug) LIKE '%acarbose%' 
          OR LOWER(p.drug) LIKE '%miglitol%' 
          OR LOWER(p.drug) LIKE '%repaglinide%' 
          OR LOWER(p.drug) LIKE '%nateglinide%' 
          THEN 'antidiabetic'
        WHEN LOWER(p.drug) LIKE '%metoprolol%' 
          OR LOWER(p.drug) LIKE '%carvedilol%' 
          OR LOWER(p.drug) LIKE '%bisoprolol%' 
          OR LOWER(p.drug) LIKE '%atenolol%' 
          OR LOWER(p.drug) LIKE '%propranolol%' 
          OR LOWER(p.drug) LIKE '%nadolol%' 
          OR LOWER(p.drug) LIKE '%timolol%' 
          OR LOWER(p.drug) LIKE '%labetalol%' 
          OR LOWER(p.drug) LIKE '%nebivolol%' 
          OR LOWER(p.drug) LIKE '%sotalol%' 
          THEN 'beta-blocker'
        WHEN LOWER(p.drug) LIKE '%lisinopril%' 
          OR LOWER(p.drug) LIKE '%enalapril%' 
          OR LOWER(p.drug) LIKE '%ramipril%' 
          OR LOWER(p.drug) LIKE '%benazepril%' 
          OR LOWER(p.drug) LIKE '%captopril%' 
          OR LOWER(p.drug) LIKE '%fosinopril%' 
          OR LOWER(p.drug) LIKE '%moexipril%' 
          OR LOWER(p.drug) LIKE '%perindopril%' 
          OR LOWER(p.drug) LIKE '%quinapril%' 
          OR LOWER(p.drug) LIKE '%trandolapril%' 
          OR LOWER(p.drug) LIKE '%losartan%' 
          OR LOWER(p.drug) LIKE '%valsartan%' 
          OR LOWER(p.drug) LIKE '%irbesartan%' 
          OR LOWER(p.drug) LIKE '%candesartan%' 
          OR LOWER(p.drug) LIKE '%telmisartan%' 
          OR LOWER(p.drug) LIKE '%olmesartan%' 
          OR LOWER(p.drug) LIKE '%azilsartan%' 
          OR LOWER(p.drug) LIKE '%sacubitril%' 
          OR LOWER(p.drug) LIKE '%entresto%' 
          THEN 'acei_arb_arni'
        WHEN LOWER(p.drug) LIKE '%furosemide%' 
          OR LOWER(p.drug) LIKE '%lasix%' 
          OR LOWER(p.drug) LIKE '%bumetanide%' 
          OR LOWER(p.drug) LIKE '%bumex%' 
          OR LOWER(p.drug) LIKE '%torsemide%' 
          OR LOWER(p.drug) LIKE '%demadex%' 
          THEN 'loop_diuretic'
        ELSE NULL
      END AS med_class,
      CASE 
        WHEN p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR) 
          AND COALESCE(p.stoptime, c.dischtime) > c.admittime 
        THEN 1 
        ELSE 0 
      END AS first_24h_flag,
      CASE 
        WHEN p.starttime < c.dischtime 
          AND COALESCE(p.stoptime, c.dischtime) > TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR)
        THEN 1 
        ELSE 0 
      END AS last_24h_flag
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN cohort c 
      ON p.hadm_id = c.hadm_id
  )
  WHERE med_class IS NOT NULL
),
status_per_class_raw AS (
  SELECT 
    hadm_id,
    med_class,
    MAX(first_24h_flag) AS first_24h,
    MAX(last_24h_flag) AS last_24h
  FROM medication_orders
  GROUP BY hadm_id, med_class
),
class_list AS (
  SELECT 'antidiabetic' AS med_class
  UNION ALL SELECT 'beta-blocker'
  UNION ALL SELECT 'acei_arb_arni'
  UNION ALL SELECT 'loop_diuretic'
),
cohort_with_classes AS (
  SELECT 
    c.hadm_id,
    cl.med_class
  FROM cohort c
  CROSS JOIN class_list cl
),
status_per_class AS (
  SELECT 
    cwc.hadm_id,
    cwc.med_class,
    COALESCE(s.first_24h, 0) AS first_24h,
    COALESCE(s.last_24h, 0) AS last_24h
  FROM cohort_with_classes cwc
  LEFT JOIN status_per_class_raw s
    ON cwc.hadm_id = s.hadm_id 
    AND cwc.med_class = s.med_class
),
class_summary AS (
  SELECT 
    med_class,
    COUNT(*) AS total_admissions,
    SUM(first_24h) AS count_first,
    SUM(last_24h) AS count_last,
    SUM(CASE WHEN first_24h = 1 AND last_24h = 1 THEN 1 ELSE 0 END) AS continued,
    SUM(CASE WHEN first_24h = 0 AND last_24h = 1 THEN 1 ELSE 0 END) AS initiated_late,
    SUM(CASE WHEN first_24h = 1 AND last_24h = 0 THEN 1 ELSE 0 END) AS discontinued
  FROM status_per_class
  GROUP BY med_class
)
SELECT 
  med_class,
  total_admissions,
  count_first,
  count_last,
  continued,
  initiated_late,
  discontinued,
  ROUND(count_first * 100.0 / total_admissions, 2) AS pct_first,
  ROUND(count_last * 100.0 / total_admissions, 2) AS pct_last
FROM class_summary
ORDER BY med_class;