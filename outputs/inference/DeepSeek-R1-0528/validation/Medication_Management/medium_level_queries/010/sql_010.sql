WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    INNER JOIN (
      SELECT DISTINCT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code LIKE '250%' AND (icd_code LIKE '%0' OR icd_code LIKE '%2')) 
        OR (icd_version = 10 AND icd_code LIKE 'E11%')
    ) t2dm ON a.hadm_id = t2dm.hadm_id
    INNER JOIN (
      SELECT DISTINCT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code LIKE '428%') 
        OR (icd_version = 10 AND icd_code LIKE 'I50%')
    ) hf ON a.hadm_id = hf.hadm_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 67 AND 77
),

med_mapping AS (
  SELECT 
    hadm_id,
    starttime,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'metformin'
      WHEN LOWER(drug) LIKE '%glipizide%' OR 
           LOWER(drug) LIKE '%glyburide%' OR 
           LOWER(drug) LIKE '%glimepiride%' THEN 'sulfonylurea'
      WHEN LOWER(drug) LIKE '%sitagliptin%' OR 
           LOWER(drug) LIKE '%saxagliptin%' OR 
           LOWER(drug) LIKE '%linagliptin%' OR 
           LOWER(drug) LIKE '%alogliptin%' THEN 'dpp4'
      WHEN LOWER(drug) LIKE '%canagliflozin%' OR 
           LOWER(drug) LIKE '%dapagliflozin%' OR 
           LOWER(drug) LIKE '%empagliflozin%' THEN 'sglt2'
      WHEN LOWER(drug) LIKE '%exenatide%' OR 
           LOWER(drug) LIKE '%liraglutide%' OR 
           LOWER(drug) LIKE '%dulaglutide%' OR 
           LOWER(drug) LIKE '%semaglutide%' THEN 'glp1'
      WHEN LOWER(drug) LIKE '%pioglitazone%' OR 
           LOWER(drug) LIKE '%rosiglitazone%' THEN 'tzd'
    END AS med_class
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    starttime IS NOT NULL
),

first_meds AS (
  SELECT 
    hadm_id, 
    med_class, 
    MIN(starttime) AS first_starttime
  FROM med_mapping
  WHERE med_class IS NOT NULL
  GROUP BY hadm_id, med_class
),

class_list AS (
  SELECT 'insulin' AS med_class UNION ALL
  SELECT 'metformin' UNION ALL
  SELECT 'sulfonylurea' UNION ALL
  SELECT 'dpp4' UNION ALL
  SELECT 'sglt2' UNION ALL
  SELECT 'glp1' UNION ALL
  SELECT 'tzd'
),

cohort_classes AS (
  SELECT 
    c.hadm_id, 
    c.admittime, 
    c.dischtime, 
    cl.med_class
  FROM cohort c
  CROSS JOIN class_list cl
),

cohort_meds AS (
  SELECT 
    cc.hadm_id, 
    cc.med_class, 
    cc.admittime, 
    cc.dischtime, 
    fm.first_starttime
  FROM cohort_classes cc
  LEFT JOIN first_meds fm 
    ON cc.hadm_id = fm.hadm_id 
    AND cc.med_class = fm.med_class
),

flag_windows AS (
  SELECT 
    hadm_id,
    med_class,
    CASE 
      WHEN first_starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 12 HOUR) THEN 1 
      ELSE 0 
    END AS first_12h,
    CASE 
      WHEN first_starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 48 HOUR) AND dischtime THEN 1 
      ELSE 0 
    END AS final_48h
  FROM cohort_meds
)

SELECT 
  med_class,
  ROUND(AVG(first_12h) * 100, 1) AS percent_first_12h,
  ROUND(AVG(final_48h) * 100, 1) AS percent_final_48h,
  ROUND((AVG(final_48h) - AVG(first_12h)) * 100, 1) AS net_change_pp
FROM flag_windows
GROUP BY med_class
ORDER BY med_class;