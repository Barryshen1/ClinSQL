WITH diag AS (
  SELECT hadm_id,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code LIKE '250%') 
             OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%')) 
          THEN 1 ELSE 0 
        END) AS diabetes,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code LIKE '428%') 
             OR (icd_version = 10 AND icd_code LIKE 'I50%') 
          THEN 1 ELSE 0 
        END) AS heart_failure
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN diag 
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    diag.diabetes = 1 
    AND diag.heart_failure = 1
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 40 AND 50
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 24
),

classes AS (
  SELECT 'antidiabetic' AS class, 
    ['insulin','metformin','glipizide','glyburide','glimepiride','sitagliptin','exenatide','liraglutide','dapagliflozin','empagliflozin','canagliflozin','acarbose','miglitol','pioglitazone','rosiglitazone','nateglinide','repaglinide','saxagliptin','linagliptin','alogliptin','semaglutide','dulaglutide','lixisenatide'] AS keywords
  UNION ALL
  SELECT 'beta-blocker', 
    ['propranolol','metoprolol','atenolol','bisoprolol','carvedilol','labetalol','nadolol','nebivolol','sotalol','timolol','pindolol','acebutolol','betaxolol','carteolol','penbutolol']
  UNION ALL
  SELECT 'acei_arb_arni', 
    ['captopril','enalapril','lisinopril','ramipril','perindopril','quinapril','fosinopril','benazepril','trandolapril','moexipril','losartan','valsartan','irbesartan','candesartan','telmisartan','olmesartan','eprosartan','azilsartan','sacubitril','entresto']
  UNION ALL
  SELECT 'loop_diuretic', 
    ['furosemide','bumetanide','torsemide','ethacrynic acid']
),

emar_classified AS (
  SELECT 
    emar.hadm_id,
    emar.charttime,
    c.class
  FROM `physionet-data.mimiciv_3_1_hosp.emar` emar
  CROSS JOIN classes c
  WHERE EXISTS (
    SELECT 1 
    FROM UNNEST(c.keywords) k 
    WHERE LOWER(emar.medication) LIKE CONCAT('%', k, '%')
  )
),

per_patient_class AS (
  SELECT 
    c.hadm_id,
    cls.class,
    MAX(CASE WHEN ec.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS first_24h_flag,
    MAX(CASE WHEN ec.charttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS last_24h_flag
  FROM cohort c
  CROSS JOIN (SELECT DISTINCT class FROM classes) cls
  LEFT JOIN emar_classified ec 
    ON c.hadm_id = ec.hadm_id 
    AND cls.class = ec.class
  GROUP BY c.hadm_id, cls.class
)

SELECT 
  class AS medication_class,
  ROUND(AVG(first_24h_flag) * 100, 2) AS pct_first_24h,
  ROUND(AVG(last_24h_flag) * 100, 2) AS pct_last_24h,
  SUM(CASE WHEN first_24h_flag = 1 AND last_24h_flag = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN first_24h_flag = 0 AND last_24h_flag = 1 THEN 1 ELSE 0 END) AS initiated_late,
  SUM(CASE WHEN first_24h_flag = 1 AND last_24h_flag = 0 THEN 1 ELSE 0 END) AS discontinued
FROM per_patient_class
GROUP BY class
ORDER BY class;