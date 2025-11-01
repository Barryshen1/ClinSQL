WITH ich_icd_codes AS (
  -- ICD codes for intracranial hemorrhage
  SELECT '430' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '431', 9 UNION ALL
  SELECT '432', 9 UNION ALL
  SELECT '4320', 9 UNION ALL
  SELECT '4321', 9 UNION ALL
  SELECT '4329', 9 UNION ALL
  SELECT 'I60', 10 UNION ALL
  SELECT 'I601', 10 UNION ALL
  SELECT 'I602', 10 UNION ALL
  SELECT 'I603', 10 UNION ALL
  SELECT 'I604', 10 UNION ALL
  SELECT 'I605', 10 UNION ALL
  SELECT 'I606', 10 UNION ALL
  SELECT 'I607', 10 UNION ALL
  SELECT 'I608', 10 UNION ALL
  SELECT 'I609', 10 UNION ALL
  SELECT 'I61', 10 UNION ALL
  SELECT 'I610', 10 UNION ALL
  SELECT 'I611', 10 UNION ALL
  SELECT 'I612', 10 UNION ALL
  SELECT 'I613', 10 UNION ALL
  SELECT 'I614', 10 UNION ALL
  SELECT 'I615', 10 UNION ALL
  SELECT 'I616', 10 UNION ALL
  SELECT 'I618', 10 UNION ALL
  SELECT 'I619', 10 UNION ALL
  SELECT 'I62', 10 UNION ALL
  SELECT 'I620', 10 UNION ALL
  SELECT 'I621', 10 UNION ALL
  SELECT 'I629', 10
),
cardiac_icd_codes AS (
  -- Cardiac complication ICD codes
  SELECT '410' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '4100', 9 UNION ALL
  SELECT '4101', 9 UNION ALL
  SELECT '4102', 9 UNION ALL
  SELECT '4103', 9 UNION ALL
  SELECT '4104', 9 UNION ALL
  SELECT '4105', 9 UNION ALL
  SELECT '4106', 9 UNION ALL
  SELECT '4107', 9 UNION ALL
  SELECT '4108', 9 UNION ALL
  SELECT '4109', 9 UNION ALL
  SELECT '427', 9 UNION ALL
  SELECT '4270', 9 UNION ALL
  SELECT '4271', 9 UNION ALL
  SELECT '4272', 9 UNION ALL
  SELECT '4273', 9 UNION ALL
  SELECT '4274', 9 UNION ALL
  SELECT '4275', 9 UNION ALL
  SELECT '4276', 9 UNION ALL
  SELECT '4277', 9 UNION ALL
  SELECT '4278', 9 UNION ALL
  SELECT '4279', 9 UNION ALL
  SELECT '428', 9 UNION ALL
  SELECT '4280', 9 UNION ALL
  SELECT '4281', 9 UNION ALL
  SELECT '4282', 9 UNION ALL
  SELECT '4283', 9 UNION ALL
  SELECT '4284', 9 UNION ALL
  SELECT '4285', 9 UNION ALL
  SELECT '4286', 9 UNION ALL
  SELECT '4287', 9 UNION ALL
  SELECT '4289', 9 UNION ALL
  SELECT 'I21', 10 UNION ALL
  SELECT 'I210', 10 UNION ALL
  SELECT 'I211', 10 UNION ALL
  SELECT 'I212', 10 UNION ALL
  SELECT 'I213', 10 UNION ALL
  SELECT 'I214', 10 UNION ALL
  SELECT 'I219', 10 UNION ALL
  SELECT 'I47', 10 UNION ALL
  SELECT 'I470', 10 UNION ALL
  SELECT 'I471', 10 UNION ALL
  SELECT 'I472', 10 UNION ALL
  SELECT 'I479', 10 UNION ALL
  SELECT 'I48', 10 UNION ALL
  SELECT 'I480', 10 UNION ALL
  SELECT 'I481', 10 UNION ALL
  SELECT 'I482', 10 UNION ALL
  SELECT 'I483', 10 UNION ALL
  SELECT 'I484', 10 UNION ALL
  SELECT 'I489', 10 UNION ALL
  SELECT 'I50', 10 UNION ALL
  SELECT 'I500', 10 UNION ALL
  SELECT 'I501', 10 UNION ALL
  SELECT 'I509', 10
),
neuro_icd_codes AS (
  -- Neurologic complication ICD codes
  SELECT '434' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '4340', 9 UNION ALL
  SELECT '4341', 9 UNION ALL
  SELECT '4349', 9 UNION ALL
  SELECT '345', 9 UNION ALL
  SELECT '3450', 9 UNION ALL
  SELECT '3451', 9 UNION ALL
  SELECT '3452', 9 UNION ALL
  SELECT '3453', 9 UNION ALL
  SELECT '3454', 9 UNION ALL
  SELECT '3455', 9 UNION ALL
  SELECT '3456', 9 UNION ALL
  SELECT '3457', 9 UNION ALL
  SELECT '3458', 9 UNION ALL
  SELECT '3459', 9 UNION ALL
  SELECT '3485', 9 UNION ALL
  SELECT 'I63', 10 UNION ALL
  SELECT 'I630', 10 UNION ALL
  SELECT 'I631', 10 UNION ALL
  SELECT 'I632', 10 UNION ALL
  SELECT 'I633', 10 UNION ALL
  SELECT 'I634', 10 UNION ALL
  SELECT 'I635', 10 UNION ALL
  SELECT 'I636', 10 UNION ALL
  SELECT 'I638', 10 UNION ALL
  SELECT 'I639', 10 UNION ALL
  SELECT 'G40', 10 UNION ALL
  SELECT 'G400', 10 UNION ALL
  SELECT 'G401', 10 UNION ALL
  SELECT 'G402', 10 UNION ALL
  SELECT 'G403', 10 UNION ALL
  SELECT 'G404', 10 UNION ALL
  SELECT 'G405', 10 UNION ALL
  SELECT 'G406', 10 UNION ALL
  SELECT 'G407', 10 UNION ALL
  SELECT 'G408', 10 UNION ALL
  SELECT 'G409', 10 UNION ALL
  SELECT 'G936', 10
),
cohort AS (
  -- Select female inpatients aged 44-54 with ICH
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions adm
    JOIN physionet-data.mimiciv_3_1_hosp.patients pat
      ON adm.subject_id = pat.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
      ON adm.hadm_id = diag.hadm_id
    JOIN ich_icd_codes ich
      ON diag.icd_code = ich.icd_code AND diag.icd_version = ich.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 44 AND 54
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
comorbidity_counts AS (
  -- Count distinct ICD codes per admission (comorbidities)
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_comorbidities
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd
  GROUP BY
    hadm_id
),
complications AS (
  -- Cardiac and neurologic complications per admission
  SELECT
    c.hadm_id,
    MAX(CASE WHEN cc.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS cardiac_complication,
    MAX(CASE WHEN nc.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS neuro_complication
  FROM
    cohort c
    LEFT JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
      ON c.hadm_id = diag.hadm_id
    LEFT JOIN cardiac_icd_codes cc
      ON diag.icd_code = cc.icd_code AND diag.icd_version = cc.icd_version
    LEFT JOIN neuro_icd_codes nc
      ON diag.icd_code = nc.icd_code AND diag.icd_version = nc.icd_version
  GROUP BY
    c.hadm_id
),
risk_scores AS (
  -- Calculate composite risk score
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    IFNULL(com.num_comorbidities, 0) AS num_comorbidities,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los,
    -- Composite risk score: age + LOS + num_comorbidities
    (c.anchor_age + TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) + IFNULL(com.num_comorbidities, 0)) AS risk_score
  FROM
    cohort c
    LEFT JOIN comorbidity_counts com
      ON c.hadm_id = com.hadm_id
),
quartiles AS (
  -- Assign quartile based on risk score
  SELECT
    *,
    NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile
  FROM
    risk_scores
),
final AS (
  -- Join complications
  SELECT
    q.*,
    comp.cardiac_complication,
    comp.neuro_complication
  FROM
    quartiles q
    LEFT JOIN complications comp
      ON q.hadm_id = comp.hadm_id
)
SELECT
  risk_quartile,
  COUNT(*) AS patient_count,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 3) AS in_hospital_mortality_rate,
  ROUND(SUM(CASE WHEN cardiac_complication = 1 THEN 1 ELSE 0 END) / COUNT(*), 3) AS cardiac_complication_rate,
  ROUND(SUM(CASE WHEN neuro_complication = 1 THEN 1 ELSE 0 END) / COUNT(*), 3) AS neuro_complication_rate,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los_survivors
FROM
  final
WHERE
  los IS NOT NULL
GROUP BY
  risk_quartile
ORDER BY
  risk_quartile;