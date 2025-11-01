WITH 
cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 36 AND 46
),
t2dm AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '250%' AND LENGTH(icd_code) >= 5 AND SUBSTR(icd_code, 5, 1) IN ('0', '2'))
    OR (icd_version = 10 AND icd_code LIKE 'E11%')
  GROUP BY hadm_id
),
heart_failure AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%')
    OR (icd_version = 10 AND icd_code LIKE 'I50%')
  GROUP BY hadm_id
),
final_cohort AS (
  SELECT c.hadm_id, c.admittime, c.dischtime
  FROM cohort c
  INNER JOIN t2dm t ON c.hadm_id = t.hadm_id
  INNER JOIN heart_failure h ON c.hadm_id = h.hadm_id
),
antidiabetic_drugs AS (
  SELECT 
    hadm_id,
    drug_class,
    starttime
  FROM (
    SELECT 
      p.hadm_id,
      p.starttime,
      CASE
        WHEN LOWER(p.drug) LIKE '%metform%' THEN 'Biguanides'
        WHEN LOWER(p.drug) LIKE '%glybur%' OR LOWER(p.drug) LIKE '%glib%' OR LOWER(p.drug) LIKE '%glime%' THEN 'Sulfonylureas'
        WHEN LOWER(p.drug) LIKE '%pioglit%' OR LOWER(p.drug) LIKE '%rosiglit%' THEN 'Thiazolidinediones'
        WHEN LOWER(p.drug) LIKE '%sitagli%' OR LOWER(p.drug) LIKE '%saxagli%' OR LOWER(p.drug) LIKE '%linagli%' OR LOWER(p.drug) LIKE '%alogli%' THEN 'DPP-4 inhibitors'
        WHEN LOWER(p.drug) LIKE '%exenat%' OR LOWER(p.drug) LIKE '%liraglut%' OR LOWER(p.drug) LIKE '%dulaglut%' OR LOWER(p.drug) LIKE '%semaglut%' THEN 'GLP-1 receptor agonists'
        WHEN LOWER(p.drug) LIKE '%canaglif%' OR LOWER(p.drug) LIKE '%dapaglif%' OR LOWER(p.drug) LIKE '%empaglif%' THEN 'SGLT2 inhibitors'
        WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulins'
        ELSE NULL
      END AS drug_class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN final_cohort fc ON p.hadm_id = fc.hadm_id
    WHERE p.starttime IS NOT NULL
  )
  WHERE drug_class IS NOT NULL
),
class_initiation AS (
  SELECT 
    ad.hadm_id,
    ad.drug_class,
    MAX(CASE WHEN ad.starttime >= fc.admittime AND ad.starttime <= fc.admittime + INTERVAL '12' HOUR THEN 1 ELSE 0 END) AS early_init,
    MAX(CASE WHEN ad.starttime >= fc.dischtime - INTERVAL '48' HOUR AND ad.starttime <= fc.dischtime THEN 1 ELSE 0 END) AS late_init
  FROM antidiabetic_drugs ad
  INNER JOIN final_cohort fc ON ad.hadm_id = fc.hadm_id
  GROUP BY ad.hadm_id, ad.drug_class
),
total_admissions AS (
  SELECT COUNT(*) AS total
  FROM final_cohort
)
SELECT 
  drug_class,
  ROUND(SUM(early_init) * 100.0 / total, 2) AS early_rate_pct,
  ROUND(SUM(late_init) * 100.0 / total, 2) AS late_rate_pct,
  ROUND((SUM(late_init) * 100.0 / total) - (SUM(early_init) * 100.0 / total), 2) AS net_change_pp
FROM class_initiation
CROSS JOIN total_admissions
GROUP BY drug_class, total
ORDER BY drug_class;