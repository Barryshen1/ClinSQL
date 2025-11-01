WITH cohort AS (
  -- Select male patients age 77-87 with both diabetes and heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  -- Age and gender filter
  WHERE p.anchor_age BETWEEN 77 AND 87
    AND p.gender = 'M'
    AND a.hospital_expire_flag = 0 -- alive at discharge (optional, can remove)
    AND EXISTS (
      -- Diabetes diagnosis
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250'))
          OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E0[89]|^E1[0-3]'))
        )
    )
    AND EXISTS (
      -- Heart failure diagnosis
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
          OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50'))
        )
    )
),

meds AS (
  -- Gather medication administrations/orders for insulin and oral agents
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- Medication time (use charttime for emar, starttime for prescriptions)
    CASE
      WHEN e.charttime IS NOT NULL THEN e.charttime
      WHEN pr.starttime IS NOT NULL THEN pr.starttime
      ELSE NULL
    END AS med_time,
    -- Drug class
    CASE
      WHEN LOWER(COALESCE(e.medication, pr.drug)) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(COALESCE(e.medication, pr.drug)) LIKE '%metformin%' THEN 'oral'
      WHEN LOWER(COALESCE(e.medication, pr.drug)) LIKE '%glipizide%' THEN 'oral'
      WHEN LOWER(COALESCE(e.medication, pr.drug)) LIKE '%glyburide%' THEN 'oral'
      WHEN LOWER(COALESCE(e.medication, pr.drug)) LIKE '%glimepiride%' THEN 'oral'
      WHEN LOWER(COALESCE(e.medication, pr.drug)) LIKE '%sitagliptin%' THEN 'oral'
      WHEN LOWER(COALESCE(e.medication, pr.drug)) LIKE '%linagliptin%' THEN 'oral'
      WHEN LOWER(COALESCE(e.medication, pr.drug)) LIKE '%pioglitazone%' THEN 'oral'
      WHEN LOWER(COALESCE(e.medication, pr.drug)) LIKE '%rosiglitazone%' THEN 'oral'
      WHEN LOWER(COALESCE(e.medication, pr.drug)) LIKE '%canagliflozin%' THEN 'oral'
      WHEN LOWER(COALESCE(e.medication, pr.drug)) LIKE '%dapagliflozin%' THEN 'oral'
      WHEN LOWER(COALESCE(e.medication, pr.drug)) LIKE '%empagliflozin%' THEN 'oral'
      ELSE NULL
    END AS drug_class,
    -- Route
    COALESCE(ed.route, pr.route) AS route
  FROM cohort c
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.emar e
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.emar_detail ed
    ON e.subject_id = ed.subject_id AND e.emar_id = ed.emar_id AND e.emar_seq = ed.emar_seq
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  WHERE
    -- Only include insulin or oral agents
    (
      LOWER(COALESCE(e.medication, pr.drug)) LIKE '%insulin%'
      OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%metformin%'
      OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%glipizide%'
      OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%glyburide%'
      OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%glimepiride%'
      OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%sitagliptin%'
      OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%linagliptin%'
      OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%pioglitazone%'
      OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%rosiglitazone%'
      OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%canagliflozin%'
      OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%dapagliflozin%'
      OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%empagliflozin%'
    )
    -- Route filter: insulin not oral, oral agents only oral
    AND (
      (LOWER(COALESCE(e.medication, pr.drug)) LIKE '%insulin%' AND NOT LOWER(COALESCE(ed.route, pr.route)) LIKE '%oral%')
      OR (
        (
          LOWER(COALESCE(e.medication, pr.drug)) LIKE '%metformin%'
          OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%glipizide%'
          OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%glyburide%'
          OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%glimepiride%'
          OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%sitagliptin%'
          OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%linagliptin%'
          OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%pioglitazone%'
          OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%rosiglitazone%'
          OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%canagliflozin%'
          OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%dapagliflozin%'
          OR LOWER(COALESCE(e.medication, pr.drug)) LIKE '%empagliflozin%'
        )
        AND (LOWER(COALESCE(ed.route, pr.route)) LIKE '%oral%' OR LOWER(COALESCE(ed.route, pr.route)) LIKE '%po%')
      )
    )
),

initiation AS (
  -- For each admission and drug class, find first initiation in each window
  SELECT
    subject_id,
    hadm_id,
    drug_class,
    MIN(CASE WHEN med_time BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 48 HOUR) THEN med_time END) AS first_0_48h,
    MIN(CASE WHEN med_time BETWEEN DATETIME_SUB(dischtime, INTERVAL 72 HOUR) AND dischtime THEN med_time END) AS first_final_72h,
    admittime,
    dischtime
  FROM meds
  WHERE drug_class IS NOT NULL
  GROUP BY subject_id, hadm_id, drug_class, admittime, dischtime
),

admission_lengths AS (
  -- Only include admissions with length >= 72h for final window
  SELECT
    subject_id,
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) AS adm_hours
  FROM cohort
),

rates AS (
  -- Calculate initiation rates per window and drug class
  SELECT
    i.drug_class,
    COUNT(DISTINCT CASE WHEN i.first_0_48h IS NOT NULL THEN CONCAT(i.subject_id, '-', i.hadm_id) END) AS n_init_0_48h,
    COUNT(DISTINCT CASE WHEN i.first_final_72h IS NOT NULL AND al.adm_hours >= 72 THEN CONCAT(i.subject_id, '-', i.hadm_id) END) AS n_init_final_72h,
    COUNT(DISTINCT CONCAT(i.subject_id, '-', i.hadm_id)) AS n_total,
    COUNT(DISTINCT CASE WHEN al.adm_hours >= 72 THEN CONCAT(i.subject_id, '-', i.hadm_id) END) AS n_total_final_72h
  FROM initiation i
  JOIN admission_lengths al
    ON i.subject_id = al.subject_id AND i.hadm_id = al.hadm_id
  GROUP BY i.drug_class
)

SELECT
  drug_class,
  SAFE_DIVIDE(n_init_0_48h, n_total) * 100 AS initiation_rate_0_48h_pct,
  SAFE_DIVIDE(n_init_final_72h, n_total_final_72h) * 100 AS initiation_rate_final_72h_pct,
  (SAFE_DIVIDE(n_init_final_72h, n_total_final_72h) - SAFE_DIVIDE(n_init_0_48h, n_total)) * 100 AS net_change_pp
FROM rates
ORDER BY drug_class;