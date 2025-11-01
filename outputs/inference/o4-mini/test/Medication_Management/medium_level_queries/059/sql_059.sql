WITH cohort AS (
  -- Female patients aged 60-70 with T2DM and HF
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
    AND LOWER(dd.long_title) LIKE '%type 2 diab%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  HAVING
    -- ensure at least one HF diagnosis as well
    SUM(CASE WHEN LOWER(dd.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) >= 1
),
denominator AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_patients
  FROM cohort
),
meds AS (
  -- classify prescriptions into drug classes
  SELECT
    c.hadm_id,
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'antidiabetics'
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'antidiabetics'
      WHEN LOWER(p.drug) LIKE '%glipizide%' THEN 'antidiabetics'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' THEN 'antidiabetics'
      WHEN LOWER(p.drug) LIKE '%metoprolol%' THEN 'beta_blockers'
      WHEN LOWER(p.drug) LIKE '%atenolol%' THEN 'beta_blockers'
      WHEN LOWER(p.drug) LIKE '%propranolol%' THEN 'beta_blockers'
      WHEN LOWER(p.drug) LIKE '%lisinopril%' THEN 'ace_arb_arni'
      WHEN LOWER(p.drug) LIKE '%enalapril%' THEN 'ace_arb_arni'
      WHEN LOWER(p.drug) LIKE '%losartan%' THEN 'ace_arb_arni'
      WHEN LOWER(p.drug) LIKE '%sacubitril-valsartan%' THEN 'ace_arb_arni'
      WHEN LOWER(p.drug) LIKE '%furosemide%' THEN 'loop_diuretics'
      WHEN LOWER(p.drug) LIKE '%bumetanide%' THEN 'loop_diuretics'
      WHEN LOWER(p.drug) LIKE '%torsemide%' THEN 'loop_diuretics'
      ELSE NULL
    END AS drug_class,
    p.starttime,
    c.admittime,
    c.dischtime
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON c.hadm_id = p.hadm_id
),
filtered_meds AS (
  -- keep only rows where we matched a drug class
  SELECT *
  FROM meds
  WHERE drug_class IS NOT NULL
),
window_counts AS (
  -- count initiation in each window, per hadm_id and drug_class
  SELECT
    drug_class,
    hadm_id,
    -- 1 if any prescription in first 48h
    MAX(CASE 
          WHEN starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR)
          THEN 1 ELSE 0 END) AS initiated_first48h_bool,
    -- 1 if any prescription in final 24h
    MAX(CASE 
          WHEN starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR) AND dischtime
          THEN 1 ELSE 0 END) AS initiated_final24h_bool
  FROM filtered_meds
  GROUP BY drug_class, hadm_id
),
agg AS (
  SELECT
    drug_class,
    COUNTIF(initiated_first48h_bool = 1) AS n_first48h,
    COUNTIF(initiated_final24h_bool = 1) AS n_final24h
  FROM window_counts
  GROUP BY drug_class
)
SELECT
  a.drug_class,
  SAFE_DIVIDE(a.n_first48h, d.total_patients) * 100 AS pct_first48h,
  SAFE_DIVIDE(a.n_final24h, d.total_patients) * 100 AS pct_final24h,
  SAFE_DIVIDE(a.n_final24h - a.n_first48h, d.total_patients) * 100 AS absolute_diff_pp
FROM agg a
CROSS JOIN denominator d
ORDER BY drug_class;