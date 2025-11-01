WITH cohort AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 49 AND 59
    AND i.hadm_id IN (
      SELECT t2dm.hadm_id
      FROM (
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          (icd_version = 10 AND icd_code LIKE 'E11%') 
          OR (icd_version = 9 AND (icd_code LIKE '2500%' OR icd_code LIKE '2502%'))
      ) t2dm
      INNER JOIN (
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          (icd_version = 10 AND icd_code LIKE 'I50%') 
          OR (icd_version = 9 AND icd_code LIKE '428%')
      ) hf ON t2dm.hadm_id = hf.hadm_id
    )
),

prescriptions_with_classes AS (
  SELECT 
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    CASE 
      WHEN LOWER(drug) LIKE '%insulin%' OR LOWER(drug) LIKE '%metformin%' 
        OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' 
        OR LOWER(drug) LIKE '%glimepiride%' OR LOWER(drug) LIKE '%pioglitazone%' 
        OR LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%dapagliflozin%' 
        OR LOWER(drug) LIKE '%empagliflozin%' OR LOWER(drug) LIKE '%canagliflozin%' 
        OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' 
        OR LOWER(drug) LIKE '%repaglinide%' OR LOWER(drug) LIKE '%nateglinide%' 
        OR LOWER(drug) LIKE '%acarbose%' OR LOWER(drug) LIKE '%miglitol%' 
        OR LOWER(drug) LIKE '%exenatide%' OR LOWER(drug) LIKE '%liraglutide%' 
        OR LOWER(drug) LIKE '%dulaglutide%' OR LOWER(drug) LIKE '%albiglutide%' 
      THEN 1 ELSE 0 
    END AS antidiabetic,
    CASE 
      WHEN LOWER(drug) LIKE '%metoprolol%' OR LOWER(drug) LIKE '%propranolol%' 
        OR LOWER(drug) LIKE '%atenolol%' OR LOWER(drug) LIKE '%carvedilol%' 
        OR LOWER(drug) LIKE '%labetalol%' OR LOWER(drug) LIKE '%bisoprolol%' 
        OR LOWER(drug) LIKE '%nebivolol%' 
      THEN 1 ELSE 0 
    END AS beta_blocker,
    CASE 
      WHEN LOWER(drug) LIKE '%lisinopril%' OR LOWER(drug) LIKE '%enalapril%' 
        OR LOWER(drug) LIKE '%ramipril%' OR LOWER(drug) LIKE '%quinapril%' 
        OR LOWER(drug) LIKE '%perindopril%' OR LOWER(drug) LIKE '%captopril%' 
        OR LOWER(drug) LIKE '%benazepril%' OR LOWER(drug) LIKE '%fosinopril%' 
        OR LOWER(drug) LIKE '%trandolapril%' OR LOWER(drug) LIKE '%losartan%' 
        OR LOWER(drug) LIKE '%valsartan%' OR LOWER(drug) LIKE '%irbesartan%' 
        OR LOWER(drug) LIKE '%candesartan%' OR LOWER(drug) LIKE '%telmisartan%' 
        OR LOWER(drug) LIKE '%olmesartan%' OR LOWER(drug) LIKE '%azilsartan%' 
        OR LOWER(drug) LIKE '%sacubitril%' OR LOWER(drug) LIKE '%entresto%' 
      THEN 1 ELSE 0 
    END AS acei_arb_arni,
    CASE 
      WHEN LOWER(drug) LIKE '%furosemide%' OR LOWER(drug) LIKE '%bumetanide%' 
        OR LOWER(drug) LIKE '%torsemide%' OR LOWER(drug) LIKE '%ethacrynic acid%' 
      THEN 1 ELSE 0 
    END AS loop_diuretic
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
),

per_stay AS (
  SELECT 
    c.stay_id,
    CAST( EXISTS (
        SELECT 1
        FROM prescriptions_with_classes p
        WHERE p.hadm_id = c.hadm_id
          AND p.antidiabetic = 1
          AND p.starttime <= LEAST(DATETIME_ADD(c.intime, INTERVAL 24 HOUR), c.outtime)
          AND (p.stoptime >= c.intime OR p.stoptime IS NULL)
      ) AS INT64 ) AS antidiabetic_first24h,
    CAST( EXISTS (
        SELECT 1
        FROM prescriptions_with_classes p
        WHERE p.hadm_id = c.hadm_id
          AND p.antidiabetic = 1
          AND p.starttime <= c.outtime
          AND (p.stoptime >= GREATEST(DATETIME_SUB(c.outtime, INTERVAL 48 HOUR), c.intime) OR p.stoptime IS NULL)
      ) AS INT64 ) AS antidiabetic_final48h,
    CAST( EXISTS (
        SELECT 1
        FROM prescriptions_with_classes p
        WHERE p.hadm_id = c.hadm_id
          AND p.beta_blocker = 1
          AND p.starttime <= LEAST(DATETIME_ADD(c.intime, INTERVAL 24 HOUR), c.outtime)
          AND (p.stoptime >= c.intime OR p.stoptime IS NULL)
      ) AS INT64 ) AS beta_blocker_first24h,
    CAST( EXISTS (
        SELECT 1
        FROM prescriptions_with_classes p
        WHERE p.hadm_id = c.hadm_id
          AND p.beta_blocker = 1
          AND p.starttime <= c.outtime
          AND (p.stoptime >= GREATEST(DATETIME_SUB(c.outtime, INTERVAL 48 HOUR), c.intime) OR p.stoptime IS NULL)
      ) AS INT64 ) AS beta_blocker_final48h,
    CAST( EXISTS (
        SELECT 1
        FROM prescriptions_with_classes p
        WHERE p.hadm_id = c.hadm_id
          AND p.acei_arb_arni = 1
          AND p.starttime <= LEAST(DATETIME_ADD(c.intime, INTERVAL 24 HOUR), c.outtime)
          AND (p.stoptime >= c.intime OR p.stoptime IS NULL)
      ) AS INT64 ) AS acei_arb_arni_first24h,
    CAST( EXISTS (
        SELECT 1
        FROM prescriptions_with_classes p
        WHERE p.hadm_id = c.hadm_id
          AND p.acei_arb_arni = 1
          AND p.starttime <= c.outtime
          AND (p.stoptime >= GREATEST(DATETIME_SUB(c.outtime, INTERVAL 48 HOUR), c.intime) OR p.stoptime IS NULL)
      ) AS INT64 ) AS acei_arb_arni_final48h,
    CAST( EXISTS (
        SELECT 1
        FROM prescriptions_with_classes p
        WHERE p.hadm_id = c.hadm_id
          AND p.loop_diuretic = 1
          AND p.starttime <= LEAST(DATETIME_ADD(c.intime, INTERVAL 24 HOUR), c.outtime)
          AND (p.stoptime >= c.intime OR p.stoptime IS NULL)
      ) AS INT64 ) AS loop_diuretic_first24h,
    CAST( EXISTS (
        SELECT 1
        FROM prescriptions_with_classes p
        WHERE p.hadm_id = c.hadm_id
          AND p.loop_diuretic = 1
          AND p.starttime <= c.outtime
          AND (p.stoptime >= GREATEST(DATETIME_SUB(c.outtime, INTERVAL 48 HOUR), c.intime) OR p.stoptime IS NULL)
      ) AS INT64 ) AS loop_diuretic_final48h
  FROM cohort c
),

per_stay_class AS (
  SELECT stay_id, 'Antidiabetic' AS drug_class, antidiabetic_first24h AS first24h, antidiabetic_final48h AS final48h FROM per_stay
  UNION ALL
  SELECT stay_id, 'Beta-Blocker', beta_blocker_first24h, beta_blocker_final48h FROM per_stay
  UNION ALL
  SELECT stay_id, 'ACEi/ARB/ARNI', acei_arb_arni_first24h, acei_arb_arni_final48h FROM per_stay
  UNION ALL
  SELECT stay_id, 'Loop Diuretic', loop_diuretic_first24h, loop_diuretic_final48h FROM per_stay
)

SELECT 
  drug_class,
  COUNT(*) AS total_patients,
  ROUND(AVG(first24h) * 100, 1) AS percent_first24h,
  ROUND(AVG(final48h) * 100, 1) AS percent_final48h,
  SUM(CASE WHEN first24h = 1 AND final48h = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN first24h = 0 AND final48h = 1 THEN 1 ELSE 0 END) AS initiated,
  SUM(CASE WHEN first24h = 1 AND final48h = 0 THEN 1 ELSE 0 END) AS discontinued
FROM per_stay_class
GROUP BY drug_class
ORDER BY drug_class;