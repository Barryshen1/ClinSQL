WITH cohort AS (
  -- Qualifying admissions for women 69-79 with T2DM and heart failure
  SELECT DISTINCT a.hadm_id, a.admittime, a.dischtime, p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
        ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
      WHERE d.hadm_id = a.hadm_id AND d.icd_version = CAST('10' AS INT64) AND icd.icd_code LIKE 'E11.%'
    )
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
        ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
      WHERE d.hadm_id = a.hadm_id AND d.icd_version = CAST('10' AS INT64) AND icd.icd_code LIKE 'I50.%'
    )
),

total_admissions AS (
  SELECT COUNT(*) AS total_hadms
  FROM cohort
),

drug_exposure AS (
  -- Insulin, first 72h
  SELECT 
    c.hadm_id, c.admittime, c.dischtime, 'first_72h' AS time_window,
    1 AS insulin_flag, 0 AS metformin_flag, 0 AS sulfonylurea_flag, 0 AS dpp4_flag, 
    0 AS sglt2_flag, 0 AS glp1_flag, 0 AS tzd_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= c.admittime 
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND pr.drug LIKE '%INSULIN%'

  UNION ALL

  -- Metformin, first 72h
  SELECT 
    c.hadm_id, c.admittime, c.dischtime, 'first_72h' AS time_window,
    0 AS insulin_flag, 1 AS metformin_flag, 0 AS sulfonylurea_flag, 0 AS dpp4_flag, 
    0 AS sglt2_flag, 0 AS glp1_flag, 0 AS tzd_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= c.admittime 
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND pr.drug LIKE '%METFORMIN%'

  UNION ALL

  -- Sulfonylurea, first 72h
  SELECT 
    c.hadm_id, c.admittime, c.dischtime, 'first_72h' AS time_window,
    0 AS insulin_flag, 0 AS metformin_flag, 1 AS sulfonylurea_flag, 0 AS dpp4_flag, 
    0 AS sglt2_flag, 0 AS glp1_flag, 0 AS tzd_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= c.admittime 
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (pr.drug LIKE '%GLIPIZIDE%' OR pr.drug LIKE '%GLYBURIDE%' OR pr.drug LIKE '%GLIMEPIRIDE%')

  UNION ALL

  -- DPP-4, first 72h
  SELECT 
    c.hadm_id, c.admittime, c.dischtime, 'first_72h' AS time_window,
    0 AS insulin_flag, 0 AS metformin_flag, 0 AS sulfonylurea_flag, 1 AS dpp4_flag, 
    0 AS sglt2_flag, 0 AS glp1_flag, 0 AS tzd_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= c.admittime 
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (pr.drug LIKE '%SITAGLIPTIN%' OR pr.drug LIKE '%LINAGLIPTIN%' OR pr.drug LIKE '%SAXAGLIPTIN%')

  UNION ALL

  -- SGLT2, first 72h
  SELECT 
    c.hadm_id, c.admittime, c.dischtime, 'first_72h' AS time_window,
    0 AS insulin_flag, 0 AS metformin_flag, 0 AS sulfonylurea_flag, 0 AS dpp4_flag, 
    1 AS sglt2_flag, 0 AS glp1_flag, 0 AS tzd_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= c.admittime 
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (pr.drug LIKE '%DAPAGLIFLOZIN%' OR pr.drug LIKE '%EMPAGLIFLOZIN%' OR pr.drug LIKE '%CANA%')

  UNION ALL

  -- GLP-1, first 72h
  SELECT 
    c.hadm_id, c.admittime, c.dischtime, 'first_72h' AS time_window,
    0 AS insulin_flag, 0 AS metformin_flag, 0 AS sulfonylurea_flag, 0 AS dpp4_flag, 
    0 AS sglt2_flag, 1 AS glp1_flag, 0 AS tzd_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= c.admittime 
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (pr.drug LIKE '%EXENATIDE%' OR pr.drug LIKE '%LIRAGLUTIDE%' OR pr.drug LIKE '%DULAGLUTIDE%')

  UNION ALL

  -- TZD, first 72h
  SELECT 
    c.hadm_id, c.admittime, c.dischtime, 'first_72h' AS time_window,
    0 AS insulin_flag, 0 AS metformin_flag, 0 AS sulfonylurea_flag, 0 AS dpp4_flag, 
    0 AS sglt2_flag, 0 AS glp1_flag, 1 AS tzd_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= c.admittime 
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (pr.drug LIKE '%PIOGLITAZONE%' OR pr.drug LIKE '%ROSIGLITAZONE%')

  UNION ALL

  -- Insulin, last 72h
  SELECT 
    c.hadm_id, c.admittime, c.dischtime, 'last_72h' AS time_window,
    1 AS insulin_flag, 0 AS metformin_flag, 0 AS sulfonylurea_flag, 0 AS dpp4_flag, 
    0 AS sglt2_flag, 0 AS glp1_flag, 0 AS tzd_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
    AND pr.starttime < c.dischtime
    AND pr.drug LIKE '%INSULIN%'

  UNION ALL

  -- Metformin, last 72h
  SELECT 
    c.hadm_id, c.admittime, c.dischtime, 'last_72h' AS time_window,
    0 AS insulin_flag, 1 AS metformin_flag, 0 AS sulfonylurea_flag, 0 AS dpp4_flag, 
    0 AS sglt2_flag, 0 AS glp1_flag, 0 AS tzd_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
    AND pr.starttime < c.dischtime
    AND pr.drug LIKE '%METFORMIN%'

  UNION ALL

  -- Sulfonylurea, last 72h
  SELECT 
    c.hadm_id, c.admittime, c.dischtime, 'last_72h' AS time_window,
    0 AS insulin_flag, 0 AS metformin_flag, 1 AS sulfonylurea_flag, 0 AS dpp4_flag, 
    0 AS sglt2_flag, 0 AS glp1_flag, 0 AS tzd_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
    AND pr.starttime < c.dischtime
    AND (pr.drug LIKE '%GLIPIZIDE%' OR pr.drug LIKE '%GLYBURIDE%' OR pr.drug LIKE '%GLIMEPIRIDE%')

  UNION ALL

  -- DPP-4, last 72h
  SELECT 
    c.hadm_id, c.admittime, c.dischtime, 'last_72h' AS time_window,
    0 AS insulin_flag, 0 AS metformin_flag, 0 AS sulfonylurea_flag, 1 AS dpp4_flag, 
    0 AS sglt2_flag, 0 AS glp1_flag, 0 AS tzd_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
    AND pr.starttime < c.dischtime
    AND (pr.drug LIKE '%SITAGLIPTIN%' OR pr.drug LIKE '%LINAGLIPTIN%' OR pr.drug LIKE '%SAXAGLIPTIN%')

  UNION ALL

  -- SGLT2, last 72h
  SELECT 
    c.hadm_id, c.admittime, c.dischtime, 'last_72h' AS time_window,
    0 AS insulin_flag, 0 AS metformin_flag, 0 AS sulfonylurea_flag, 0 AS dpp4_flag, 
    1 AS sglt2_flag, 0 AS glp1_flag, 0 AS tzd_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
    AND pr.starttime < c.dischtime
    AND (pr.drug LIKE '%DAPAGLIFLOZIN%' OR pr.drug LIKE '%EMPAGLIFLOZIN%' OR pr.drug LIKE '%CANA%')

  UNION ALL

  -- GLP-1, last 72h
  SELECT 
    c.hadm_id, c.admittime, c.dischtime, 'last_72h' AS time_window,
    0 AS insulin_flag, 0 AS metformin_flag, 0 AS sulfonylurea_flag, 0 AS dpp4_flag, 
    0 AS sglt2_flag, 1 AS glp1_flag, 0 AS tzd_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
    AND pr.starttime < c.dischtime
    AND (pr.drug LIKE '%EXENATIDE%' OR pr.drug LIKE '%LIRAGLUTIDE%' OR pr.drug LIKE '%DULAGLUTIDE%')

  UNION ALL

  -- TZD, last 72h
  SELECT 
    c.hadm_id, c.admittime, c.dischtime, 'last_72h' AS time_window,
    0 AS insulin_flag, 0 AS metformin_flag, 0 AS sulfonylurea_flag, 0 AS dpp4_flag, 
    0 AS sglt2_flag, 0 AS glp1_flag, 1 AS tzd_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
    AND pr.starttime < c.dischtime
    AND (pr.drug LIKE '%PIOGLITAZONE%' OR pr.drug LIKE '%ROSIGLITAZONE%')
),

summary AS (
  SELECT 
    time_window,
    SUM(insulin_flag) AS num_insulin,
    SUM(metformin_flag) AS num_metformin,
    SUM(sulfonylurea_flag) AS num_sulfonylurea,
    SUM(dpp4_flag) AS num_dpp4,
    SUM(sglt2_flag) AS num_sglt2,
    SUM(glp1_flag) AS num_glp1,
    SUM(tzd_flag) AS num_tzd
  FROM drug_exposure
  GROUP BY time_window
)

SELECT 
  'Insulin' AS drug_class, time_window,
  ROUND((num_insulin * 100.0 / t.total_hadms), 2) AS percentage
FROM summary s
CROSS JOIN total_admissions t
UNION ALL
SELECT 'Metformin', time_window, ROUND((num_metformin * 100.0 / t.total_hadms), 2)
FROM summary s CROSS JOIN total_admissions t
UNION ALL
SELECT 'Sulfonylurea', time_window, ROUND((num_sulfonylurea * 100.0 / t.total_hadms), 2)
FROM summary s CROSS JOIN total_admissions t
UNION ALL
SELECT 'DPP-4', time_window, ROUND((num_dpp4 * 100.0 / t.total_hadms), 2)
FROM summary s CROSS JOIN total_admissions t
UNION ALL
SELECT 'SGLT2', time_window, ROUND((num_sglt2 * 100.0 / t.total_hadms), 2)
FROM summary s CROSS JOIN total_admissions t
UNION ALL
SELECT 'GLP-1', time_window, ROUND((num_glp1 * 100.0 / t.total_hadms), 2)
FROM summary s CROSS JOIN total_admissions t
UNION ALL
SELECT 'TZD', time_window, ROUND((num_tzd * 100.0 / t.total_hadms), 2)
FROM summary s CROSS JOIN total_admissions t
ORDER BY time_window, drug_class;