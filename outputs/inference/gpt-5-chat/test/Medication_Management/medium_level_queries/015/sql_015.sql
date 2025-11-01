WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    -- ensure non-null times
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- filter to admissions with both diabetes and acute HF
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM (
        SELECT hadm_id,
               MAX(CASE WHEN (di.icd_version = 10 AND di.icd_code LIKE 'E1%')
                         OR (di.icd_version = 9 AND di.icd_code LIKE '250%')
                         THEN 1 ELSE 0 END) AS has_diabetes,
               MAX(CASE WHEN (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
                         OR (di.icd_version = 9 AND di.icd_code LIKE '428%')
                         THEN 1 ELSE 0 END) AS has_ahf
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        GROUP BY hadm_id
      )
      WHERE has_diabetes = 1 AND has_ahf = 1
    )
),
med_flags AS (
  SELECT
    c.hadm_id,
    -- first 24h flags
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_first24h,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 1 ELSE 0 END) AS metformin_first24h,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glimepiride%' THEN 1 ELSE 0 END) AS sulfonylurea_first24h,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' THEN 1 ELSE 0 END) AS dpp4_first24h,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%' THEN 1 ELSE 0 END) AS sglt2_first24h,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%dulaglutide%' THEN 1 ELSE 0 END) AS glp1_first24h,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' THEN 1 ELSE 0 END) AS tzd_first24h,
    -- final 12h flags
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 
      CASE WHEN pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END ELSE 0 END) AS insulin_final12h,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 
      CASE WHEN pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END ELSE 0 END) AS metformin_final12h,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glimepiride%' THEN 
      CASE WHEN pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END ELSE 0 END) AS sulfonylurea_final12h,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' THEN 
      CASE WHEN pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END ELSE 0 END) AS dpp4_final12h,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%' THEN 
      CASE WHEN pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END ELSE 0 END) AS sglt2_final12h,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%dulaglutide%' THEN 
      CASE WHEN pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END ELSE 0 END) AS glp1_final12h,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' THEN 
      CASE WHEN pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END ELSE 0 END) AS tzd_final12h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
   AND pr.starttime IS NOT NULL
   AND (
     (pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR))
     OR (pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime)
   )
  GROUP BY c.hadm_id
),
summary AS (
  SELECT
    COUNT(*) AS total_admissions,
    100*SUM(insulin_first24h)/COUNT(*) AS insulin_first24h_pct,
    100*SUM(insulin_final12h)/COUNT(*) AS insulin_final12h_pct,
    100*SUM(insulin_final12h)/COUNT(*) - 100*SUM(insulin_first24h)/COUNT(*) AS insulin_net_pp,
    100*SUM(metformin_first24h)/COUNT(*) AS metformin_first24h_pct,
    100*SUM(metformin_final12h)/COUNT(*) AS metformin_final12h_pct,
    100*SUM(metformin_final12h)/COUNT(*) - 100*SUM(metformin_first24h)/COUNT(*) AS metformin_net_pp,
    100*SUM(sulfonylurea_first24h)/COUNT(*) AS sulfonylurea_first24h_pct,
    100*SUM(sulfonylurea_final12h)/COUNT(*) AS sulfonylurea_final12h_pct,
    100*SUM(sulfonylurea_final12h)/COUNT(*) - 100*SUM(sulfonylurea_first24h)/COUNT(*) AS sulfonylurea_net_pp,
    100*SUM(dpp4_first24h)/COUNT(*) AS dpp4_first24h_pct,
    100*SUM(dpp4_final12h)/COUNT(*) AS dpp4_final12h_pct,
    100*SUM(dpp4_final12h)/COUNT(*) - 100*SUM(dpp4_first24h)/COUNT(*) AS dpp4_net_pp,
    100*SUM(sglt2_first24h)/COUNT(*) AS sglt2_first24h_pct,
    100*SUM(sglt2_final12h)/COUNT(*) AS sglt2_final12h_pct,
    100*SUM(sglt2_final12h)/COUNT(*) - 100*SUM(sglt2_first24h)/COUNT(*) AS sglt2_net_pp,
    100*SUM(glp1_first24h)/COUNT(*) AS glp1_first24h_pct,
    100*SUM(glp1_final12h)/COUNT(*) AS glp1_final12h_pct,
    100*SUM(glp1_final12h)/COUNT(*) - 100*SUM(glp1_first24h)/COUNT(*) AS glp1_net_pp,
    100*SUM(tzd_first24h)/COUNT(*) AS tzd_first24h_pct,
    100*SUM(tzd_final12h)/COUNT(*) AS tzd_final12h_pct,
    100*SUM(tzd_final12h)/COUNT(*) - 100*SUM(tzd_first24h)/COUNT(*) AS tzd_net_pp
  FROM med_flags
)
SELECT * FROM summary;