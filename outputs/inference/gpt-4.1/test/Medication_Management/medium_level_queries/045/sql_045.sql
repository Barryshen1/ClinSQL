WITH cohort AS (
  -- Select female patients age 54-64
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 54 AND 64
),
diabetes_admissions AS (
  -- Admissions with diabetes diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND LEFT(icd_code,3) = '250')
    OR (icd_version = 10 AND LEFT(icd_code,3) IN ('E08','E09','E10','E11','E13'))
),
hf_admissions AS (
  -- Admissions with heart failure diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND LEFT(icd_code,3) = '428')
    OR (icd_version = 10 AND LEFT(icd_code,3) = 'I50')
),
target_admissions AS (
  -- Admissions with both diabetes and heart failure
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime
  FROM cohort c
  JOIN diabetes_admissions d ON c.hadm_id = d.hadm_id
  JOIN hf_admissions h ON c.hadm_id = h.hadm_id
  WHERE
    DATETIME_DIFF(c.dischtime, c.admittime, HOUR) >= 48 -- Only admissions >=48h
),
meds AS (
  -- Medication administrations from EMAR and prescriptions
  SELECT
    e.subject_id,
    e.hadm_id,
    e.charttime,
    LOWER(e.medication) AS med_name,
    LOWER(ed.product_description) AS prod_desc,
    LOWER(ed.route) AS route
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` e
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
      ON e.subject_id = ed.subject_id AND e.emar_id = ed.emar_id AND e.emar_seq = ed.emar_seq
  UNION ALL
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime AS charttime,
    LOWER(pr.drug) AS med_name,
    LOWER(pr.drug) AS prod_desc,
    LOWER(pr.route) AS route
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
),
meds_classified AS (
  -- Classify medications as insulin or oral agent
  SELECT
    m.subject_id,
    m.hadm_id,
    m.charttime,
    CASE
      WHEN m.med_name LIKE '%insulin%' OR m.prod_desc LIKE '%insulin%' THEN 'insulin'
      WHEN (
        m.med_name LIKE '%metformin%' OR m.prod_desc LIKE '%metformin%' OR
        m.med_name LIKE '%glipizide%' OR m.prod_desc LIKE '%glipizide%' OR
        m.med_name LIKE '%glyburide%' OR m.prod_desc LIKE '%glyburide%' OR
        m.med_name LIKE '%glimepiride%' OR m.prod_desc LIKE '%glimepiride%' OR
        m.med_name LIKE '%sitagliptin%' OR m.prod_desc LIKE '%sitagliptin%' OR
        m.med_name LIKE '%pioglitazone%' OR m.prod_desc LIKE '%pioglitazone%' OR
        m.med_name LIKE '%repaglinide%' OR m.prod_desc LIKE '%repaglinide%' OR
        m.med_name LIKE '%canagliflozin%' OR m.prod_desc LIKE '%canagliflozin%' OR
        m.med_name LIKE '%dapagliflozin%' OR m.prod_desc LIKE '%dapagliflozin%' OR
        m.med_name LIKE '%empagliflozin%' OR m.prod_desc LIKE '%empagliflozin%' OR
        m.med_name LIKE '%linagliptin%' OR m.prod_desc LIKE '%linagliptin%' OR
        m.med_name LIKE '%alogliptin%' OR m.prod_desc LIKE '%alogliptin%' OR
        m.med_name LIKE '%rosiglitazone%' OR m.prod_desc LIKE '%rosiglitazone%' OR
        m.med_name LIKE '%tolbutamide%' OR m.prod_desc LIKE '%tolbutamide%' OR
        m.med_name LIKE '%chlorpropamide%' OR m.prod_desc LIKE '%chlorpropamide%' OR
        m.med_name LIKE '%acarbose%' OR m.prod_desc LIKE '%acarbose%' OR
        m.med_name LIKE '%miglitol%' OR m.prod_desc LIKE '%miglitol%'
      )
      AND (m.route LIKE '%po%' OR m.route LIKE '%oral%' OR m.route LIKE '%by mouth%')
      THEN 'oral_agent'
      ELSE NULL
    END AS med_type
  FROM meds m
  WHERE
    -- Only keep insulin or oral agent
    (
      m.med_name LIKE '%insulin%' OR m.prod_desc LIKE '%insulin%' OR
      (
        (
          m.med_name LIKE '%metformin%' OR m.prod_desc LIKE '%metformin%' OR
          m.med_name LIKE '%glipizide%' OR m.prod_desc LIKE '%glipizide%' OR
          m.med_name LIKE '%glyburide%' OR m.prod_desc LIKE '%glyburide%' OR
          m.med_name LIKE '%glimepiride%' OR m.prod_desc LIKE '%glimepiride%' OR
          m.med_name LIKE '%sitagliptin%' OR m.prod_desc LIKE '%sitagliptin%' OR
          m.med_name LIKE '%pioglitazone%' OR m.prod_desc LIKE '%pioglitazone%' OR
          m.med_name LIKE '%repaglinide%' OR m.prod_desc LIKE '%repaglinide%' OR
          m.med_name LIKE '%canagliflozin%' OR m.prod_desc LIKE '%canagliflozin%' OR
          m.med_name LIKE '%dapagliflozin%' OR m.prod_desc LIKE '%dapagliflozin%' OR
          m.med_name LIKE '%empagliflozin%' OR m.prod_desc LIKE '%empagliflozin%' OR
          m.med_name LIKE '%linagliptin%' OR m.prod_desc LIKE '%linagliptin%' OR
          m.med_name LIKE '%alogliptin%' OR m.prod_desc LIKE '%alogliptin%' OR
          m.med_name LIKE '%rosiglitazone%' OR m.prod_desc LIKE '%rosiglitazone%' OR
          m.med_name LIKE '%tolbutamide%' OR m.prod_desc LIKE '%tolbutamide%' OR
          m.med_name LIKE '%chlorpropamide%' OR m.prod_desc LIKE '%chlorpropamide%' OR
          m.med_name LIKE '%acarbose%' OR m.prod_desc LIKE '%acarbose%' OR
          m.med_name LIKE '%miglitol%' OR m.prod_desc LIKE '%miglitol%'
        )
        AND (m.route LIKE '%po%' OR m.route LIKE '%oral%' OR m.route LIKE '%by mouth%')
      )
    )
),
adm_meds_window AS (
  -- For each admission, flag insulin/oral agent in first 12h and final 48h
  SELECT
    ta.subject_id,
    ta.hadm_id,
    ta.admittime,
    ta.dischtime,
    MAX(CASE WHEN mc.med_type = 'insulin'
             AND mc.charttime >= ta.admittime
             AND mc.charttime < DATETIME_ADD(ta.admittime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS insulin_first12h,
    MAX(CASE WHEN mc.med_type = 'oral_agent'
             AND mc.charttime >= ta.admittime
             AND mc.charttime < DATETIME_ADD(ta.admittime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS oral_first12h,
    MAX(CASE WHEN mc.med_type = 'insulin'
             AND mc.charttime >= DATETIME_SUB(ta.dischtime, INTERVAL 48 HOUR)
             AND mc.charttime < ta.dischtime
             THEN 1 ELSE 0 END) AS insulin_final48h,
    MAX(CASE WHEN mc.med_type = 'oral_agent'
             AND mc.charttime >= DATETIME_SUB(ta.dischtime, INTERVAL 48 HOUR)
             AND mc.charttime < ta.dischtime
             THEN 1 ELSE 0 END) AS oral_final48h
  FROM
    target_admissions ta
    LEFT JOIN meds_classified mc
      ON ta.subject_id = mc.subject_id AND ta.hadm_id = mc.hadm_id
  GROUP BY ta.subject_id, ta.hadm_id, ta.admittime, ta.dischtime
),
prevalence AS (
  -- Calculate prevalence and net change
  SELECT
    COUNT(*) AS n_admissions,
    SAFE_DIVIDE(SUM(insulin_first12h), COUNT(*)) AS insulin_first12h_prev,
    SAFE_DIVIDE(SUM(insulin_final48h), COUNT(*)) AS insulin_final48h_prev,
    SAFE_DIVIDE(SUM(oral_first12h), COUNT(*)) AS oral_first12h_prev,
    SAFE_DIVIDE(SUM(oral_final48h), COUNT(*)) AS oral_final48h_prev,
    -- Net change in percentage points
    (SAFE_DIVIDE(SUM(insulin_final48h), COUNT(*)) - SAFE_DIVIDE(SUM(insulin_first12h), COUNT(*))) * 100 AS insulin_net_change_pp,
    (SAFE_DIVIDE(SUM(oral_final48h), COUNT(*)) - SAFE_DIVIDE(SUM(oral_first12h), COUNT(*))) * 100 AS oral_net_change_pp
  FROM adm_meds_window
)
SELECT
  n_admissions,
  ROUND(insulin_first12h_prev * 100,1) AS insulin_first12h_percent,
  ROUND(insulin_final48h_prev * 100,1) AS insulin_final48h_percent,
  ROUND(insulin_net_change_pp,1) AS insulin_net_change_pp,
  ROUND(oral_first12h_prev * 100,1) AS oral_first12h_percent,
  ROUND(oral_final48h_prev * 100,1) AS oral_final48h_percent,
  ROUND(oral_net_change_pp,1) AS oral_net_change_pp
FROM prevalence
;