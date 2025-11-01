WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR) AS first72_end,
    DATETIME_SUB(adm.dischtime, INTERVAL 72 HOUR) AS last72_start
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 69 AND 79
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 10 AND diag.icd_code LIKE 'E11%') OR
          (diag.icd_version = 9 AND diag.icd_code LIKE '250%' AND (diag.icd_code LIKE '%0' OR diag.icd_code LIKE '%2'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%') OR
          (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
        )
    )
),
drug_classes AS (
  SELECT 
    em.subject_id,
    em.hadm_id,
    em.charttime,
    em.medication,
    c.admittime,
    c.dischtime,
    c.first72_end,
    c.last72_start,
    CASE
      WHEN LOWER(em.medication) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(em.medication) LIKE '%metformin%' THEN 'metformin'
      WHEN LOWER(em.medication) LIKE '%glyburide%' OR LOWER(em.medication) LIKE '%glipizide%' OR LOWER(em.medication) LIKE '%glimepiride%' THEN 'sulfonylurea'
      WHEN LOWER(em.medication) LIKE '%sitagliptin%' OR LOWER(em.medication) LIKE '%saxagliptin%' OR LOWER(em.medication) LIKE '%linagliptin%' OR LOWER(em.medication) LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN LOWER(em.medication) LIKE '%canagliflozin%' OR LOWER(em.medication) LIKE '%dapagliflozin%' OR LOWER(em.medication) LIKE '%empagliflozin%' THEN 'SGLT2'
      WHEN LOWER(em.medication) LIKE '%liraglutide%' OR LOWER(em.medication) LIKE '%dulaglutide%' OR LOWER(em.medication) LIKE '%semaglutide%' OR LOWER(em.medication) LIKE '%exenatide%' THEN 'GLP-1'
      WHEN LOWER(em.medication) LIKE '%pioglitazone%' OR LOWER(em.medication) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.emar` em
  INNER JOIN cohort c
    ON em.hadm_id = c.hadm_id
  WHERE em.charttime IS NOT NULL
),
first72 AS (
  SELECT
    hadm_id,
    drug_class,
    COUNT(DISTINCT subject_id) AS cnt_patients
  FROM drug_classes
  WHERE charttime BETWEEN admittime AND first72_end
  GROUP BY hadm_id, drug_class
),
last72 AS (
  SELECT
    hadm_id,
    drug_class,
    COUNT(DISTINCT subject_id) AS cnt_patients
  FROM drug_classes
  WHERE charttime >= last72_start AND charttime <= dischtime
  GROUP BY hadm_id, drug_class
),
total_cohort AS (
  SELECT COUNT(DISTINCT hadm_id) AS total
  FROM cohort
)
SELECT
  dc.drug_class,
  ROUND(100.0 * COUNT(DISTINCT f72.hadm_id) / total, 2) AS first_72_hours_percent,
  ROUND(100.0 * COUNT(DISTINCT l72.hadm_id) / total, 2) AS last_72_hours_percent
FROM (
  SELECT DISTINCT drug_class
  FROM drug_classes
  WHERE drug_class IS NOT NULL
) dc
CROSS JOIN total_cohort
LEFT JOIN first72 f72 ON dc.drug_class = f72.drug_class
LEFT JOIN last72 l72 ON dc.drug_class = l72.drug_class
GROUP BY dc.drug_class, total
ORDER BY dc.drug_class;