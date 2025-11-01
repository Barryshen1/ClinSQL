WITH cohort AS (
  -- Select female inpatients aged 81-91 with T2DM and heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND EXISTS (
      -- T2DM diagnosis
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d1
      WHERE d1.hadm_id = a.hadm_id
        AND (
          -- ICD-10 E11.x
          (d1.icd_version = 10 AND REGEXP_CONTAINS(d1.icd_code, r'^E11'))
          -- ICD-9 250.x0 or 250.x2
          OR (d1.icd_version = 9 AND REGEXP_CONTAINS(d1.icd_code, r'^250[0-9][02]'))
        )
    )
    AND EXISTS (
      -- Heart failure diagnosis
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d2
      WHERE d2.hadm_id = a.hadm_id
        AND (
          -- ICD-10 I50.x
          (d2.icd_version = 10 AND REGEXP_CONTAINS(d2.icd_code, r'^I50'))
          -- ICD-9 428.x
          OR (d2.icd_version = 9 AND REGEXP_CONTAINS(d2.icd_code, r'^428'))
        )
    )
),

drug_classes AS (
  -- Map drugs to classes
  SELECT 'metformin' AS drug_class, 'metformin' AS keyword
  UNION ALL SELECT 'sulfonylurea', 'glyburide'
  UNION ALL SELECT 'sulfonylurea', 'glipizide'
  UNION ALL SELECT 'sulfonylurea', 'glimepiride'
  UNION ALL SELECT 'sulfonylurea', 'tolbutamide'
  UNION ALL SELECT 'sulfonylurea', 'chlorpropamide'
  UNION ALL SELECT 'sulfonylurea', 'tolazamide'
  UNION ALL SELECT 'dpp4', 'sitagliptin'
  UNION ALL SELECT 'dpp4', 'saxagliptin'
  UNION ALL SELECT 'dpp4', 'linagliptin'
  UNION ALL SELECT 'dpp4', 'alogliptin'
  UNION ALL SELECT 'sglt2', 'canagliflozin'
  UNION ALL SELECT 'sglt2', 'dapagliflozin'
  UNION ALL SELECT 'sglt2', 'empagliflozin'
  UNION ALL SELECT 'sglt2', 'ertugliflozin'
  UNION ALL SELECT 'tzd', 'pioglitazone'
  UNION ALL SELECT 'tzd', 'rosiglitazone'
),

drug_exposure AS (
  -- Find drug exposures in first 72h and final 48h from prescriptions
  SELECT
    c.subject_id,
    c.hadm_id,
    dc.drug_class,
    MAX(CASE WHEN pr.starttime >= c.admittime AND pr.starttime < DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS exposed_first_72h,
    MAX(CASE WHEN pr.starttime >= DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND pr.starttime < c.dischtime THEN 1 ELSE 0 END) AS exposed_final_48h
  FROM cohort c
  JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON pr.hadm_id = c.hadm_id
  JOIN drug_classes dc
    ON LOWER(pr.drug) LIKE CONCAT('%', dc.keyword, '%')
  GROUP BY c.subject_id, c.hadm_id, dc.drug_class

  UNION ALL

  -- Find drug exposures in first 72h and final 48h from EMAR
  SELECT
    c.subject_id,
    c.hadm_id,
    dc.drug_class,
    MAX(CASE WHEN em.charttime >= c.admittime AND em.charttime < DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS exposed_first_72h,
    MAX(CASE WHEN em.charttime >= DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND em.charttime < c.dischtime THEN 1 ELSE 0 END) AS exposed_final_48h
  FROM cohort c
  JOIN physionet-data.mimiciv_3_1_hosp.emar em
    ON em.hadm_id = c.hadm_id
  JOIN drug_classes dc
    ON LOWER(em.medication) LIKE CONCAT('%', dc.keyword, '%')
  GROUP BY c.subject_id, c.hadm_id, dc.drug_class
),

drug_exposure_agg AS (
  -- Aggregate exposures per admission and drug class
  SELECT
    subject_id,
    hadm_id,
    drug_class,
    MAX(exposed_first_72h) AS exposed_first_72h,
    MAX(exposed_final_48h) AS exposed_final_48h
  FROM drug_exposure
  GROUP BY subject_id, hadm_id, drug_class
),

prevalence AS (
  -- Calculate prevalence for each drug class and time window
  SELECT
    dc.drug_class,
    COUNT(DISTINCT CASE WHEN dea.exposed_first_72h = 1 THEN dea.hadm_id END) AS n_first_72h,
    COUNT(DISTINCT CASE WHEN dea.exposed_final_48h = 1 THEN dea.hadm_id END) AS n_final_48h,
    COUNT(DISTINCT c.hadm_id) AS n_total
  FROM drug_classes dc
  LEFT JOIN drug_exposure_agg dea
    ON dea.drug_class = dc.drug_class
  CROSS JOIN (SELECT DISTINCT hadm_id FROM cohort) c
  GROUP BY dc.drug_class
)

SELECT
  drug_class,
  ROUND(100.0 * n_first_72h / n_total, 2) AS prevalence_first_72h,
  ROUND(100.0 * n_final_48h / n_total, 2) AS prevalence_final_48h,
  ROUND(100.0 * (n_final_48h - n_first_72h) / n_total, 2) AS absolute_pp_difference
FROM prevalence
ORDER BY drug_class;