WITH admissions_with_age AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
diabetes_admissions AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '250%')
    OR (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'))
  GROUP BY hadm_id
),
acute_hf_admissions AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%')
    OR (icd_version = 10 AND (
      icd_code LIKE 'I50.2%' OR 
      icd_code LIKE 'I50.3%' OR 
      icd_code LIKE 'I50.4%' OR 
      icd_code LIKE 'I50.81%' OR 
      icd_code = 'I50.84'
    ))
  GROUP BY hadm_id
),
population_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM admissions_with_age a
  WHERE a.age_at_adm BETWEEN 42 AND 52
    AND a.hadm_id IN (SELECT hadm_id FROM diabetes_admissions)
    AND a.hadm_id IN (SELECT hadm_id FROM acute_hf_admissions)
),
population AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    admittime AS window1_start,
    LEAST(TIMESTAMP_ADD(admittime, INTERVAL '24' HOUR), dischtime) AS window1_end,
    GREATEST(TIMESTAMP_SUB(dischtime, INTERVAL '12' HOUR), admittime) AS window2_start,
    dischtime AS window2_end
  FROM population_admissions
),
meds AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    p.stoptime,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'SGLT2'
      WHEN LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%semaglutide%' THEN 'GLP-1'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN population pop
    ON p.hadm_id = pop.hadm_id
),
window1_flags AS (
  SELECT 
    pop.hadm_id,
    MAX(CASE WHEN m.drug_class = 'Insulin' THEN 1 ELSE 0 END) AS insulin_w1,
    MAX(CASE WHEN m.drug_class = 'Metformin' THEN 1 ELSE 0 END) AS metformin_w1,
    MAX(CASE WHEN m.drug_class = 'Sulfonylurea' THEN 1 ELSE 0 END) AS sulfonylurea_w1,
    MAX(CASE WHEN m.drug_class = 'DPP-4' THEN 1 ELSE 0 END) AS dpp4_w1,
    MAX(CASE WHEN m.drug_class = 'SGLT2' THEN 1 ELSE 0 END) AS sglt2_w1,
    MAX(CASE WHEN m.drug_class = 'GLP-1' THEN 1 ELSE 0 END) AS glp1_w1,
    MAX(CASE WHEN m.drug_class = 'TZD' THEN 1 ELSE 0 END) AS tzd_w1
  FROM population pop
  LEFT JOIN meds m
    ON pop.hadm_id = m.hadm_id
    AND m.starttime < pop.window1_end
    AND (m.stoptime IS NULL OR m.stoptime > pop.window1_start)
  GROUP BY pop.hadm_id
),
window2_flags AS (
  SELECT 
    pop.hadm_id,
    MAX(CASE WHEN m.drug_class = 'Insulin' THEN 1 ELSE 0 END) AS insulin_w2,
    MAX(CASE WHEN m.drug_class = 'Metformin' THEN 1 ELSE 0 END) AS metformin_w2,
    MAX(CASE WHEN m.drug_class = 'Sulfonylurea' THEN 1 ELSE 0 END) AS sulfonylurea_w2,
    MAX(CASE WHEN m.drug_class = 'DPP-4' THEN 1 ELSE 0 END) AS dpp4_w2,
    MAX(CASE WHEN m.drug_class = 'SGLT2' THEN 1 ELSE 0 END) AS sglt2_w2,
    MAX(CASE WHEN m.drug_class = 'GLP-1' THEN 1 ELSE 0 END) AS glp1_w2,
    MAX(CASE WHEN m.drug_class = 'TZD' THEN 1 ELSE 0 END) AS tzd_w2
  FROM population pop
  LEFT JOIN meds m
    ON pop.hadm_id = m.hadm_id
    AND m.starttime < pop.window2_end
    AND (m.stoptime IS NULL OR m.stoptime > pop.window2_start)
  GROUP BY pop.hadm_id
),
flags_combined AS (
  SELECT 
    w1.hadm_id,
    w1.insulin_w1, w2.insulin_w2,
    w1.metformin_w1, w2.metformin_w2,
    w1.sulfonylurea_w1, w2.sulfonylurea_w2,
    w1.dpp4_w1, w2.dpp4_w2,
    w1.sglt2_w1, w2.sglt2_w2,
    w1.glp1_w1, w2.glp1_w2,
    w1.tzd_w1, w2.tzd_w2
  FROM window1_flags w1
  INNER JOIN window2_flags w2
    ON w1.hadm_id = w2.hadm_id
),
unpivoted AS (
  SELECT hadm_id, 'Insulin' AS drug_class, insulin_w1 AS in_window1, insulin_w2 AS in_window2 FROM flags_combined
  UNION ALL
  SELECT hadm_id, 'Metformin', metformin_w1, metformin_w2 FROM flags_combined
  UNION ALL
  SELECT hadm_id, 'Sulfonylurea', sulfonylurea_w1, sulfonylurea_w2 FROM flags_combined
  UNION ALL
  SELECT hadm_id, 'DPP-4', dpp4_w1, dpp4_w2 FROM flags_combined
  UNION ALL
  SELECT hadm_id, 'SGLT2', sglt2_w1, sglt2_w2 FROM flags_combined
  UNION ALL
  SELECT hadm_id, 'GLP-1', glp1_w1, glp1_w2 FROM flags_combined
  UNION ALL
  SELECT hadm_id, 'TZD', tzd_w1, tzd_w2 FROM flags_combined
)
SELECT 
  drug_class,
  AVG(in_window1) * 100 AS first_24h_pct,
  AVG(in_window2) * 100 AS final_12h_pct,
  (AVG(in_window2) - AVG(in_window1)) * 100 AS net_change
FROM unpivoted
GROUP BY drug_class
ORDER BY 
  CASE drug_class
    WHEN 'Insulin' THEN 1
    WHEN 'Metformin' THEN 2
    WHEN 'Sulfonylurea' THEN 3
    WHEN 'DPP-4' THEN 4
    WHEN 'SGLT2' THEN 5
    WHEN 'GLP-1' THEN 6
    WHEN 'TZD' THEN 7
  END;