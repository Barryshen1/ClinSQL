WITH diabetic_hf_admissions AS (
  -- Identify admissions of 77-87 y/o male patients with both diabetes and heart failure
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
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
      ON d.icd_code = ddi.icd_code
      AND d.icd_version = ddi.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND (
      LOWER(ddi.long_title) LIKE '%diabetes%'
      OR LOWER(ddi.long_title) LIKE '%dm %'
      OR LOWER(ddi.long_title) LIKE '%dm%'
      OR LOWER(ddi.long_title) LIKE '%heart failure%'
    )
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  HAVING
    COUNT(DISTINCT
      CASE
        WHEN LOWER(ddi.long_title) LIKE '%diabetes%' THEN 'diabetes'
        WHEN LOWER(ddi.long_title) LIKE '%heart failure%' THEN 'heart_failure'
      END
    ) = 2
),
cohort_count AS (
  -- Total number of admissions in the cohort
  SELECT
    COUNT(DISTINCT hadm_id) AS total_admissions
  FROM diabetic_hf_admissions
),
med_inits AS (
  -- For each hadm, flag initiation in each window and class
  SELECT
    dha.hadm_id,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%'
        OR LOWER(p.drug) LIKE '%metformin%'
        OR LOWER(p.drug) LIKE '%glipizide%'
        OR LOWER(p.drug) LIKE '%glyburide%'
        OR LOWER(p.drug) LIKE '%glimepiride%'
      THEN 'Antidiabetic'
      WHEN LOWER(p.drug) LIKE '%olol%'
      THEN 'Beta-blocker'
      WHEN LOWER(p.drug) LIKE '%pril%'
        OR LOWER(p.drug) LIKE '%sartan%'
        OR LOWER(p.drug) LIKE '%sacubitril%'
      THEN 'ACEi/ARB/ARNI'
      WHEN LOWER(p.drug) LIKE '%furosemide%'
        OR LOWER(p.drug) LIKE '%bumetanide%'
        OR LOWER(p.drug) LIKE '%torsemide%'
      THEN 'Loop diuretic'
      ELSE NULL
    END AS drug_class,
    MAX(CASE
      WHEN p.starttime BETWEEN dha.admittime AND TIMESTAMP_ADD(dha.admittime, INTERVAL 48 HOUR)
      THEN 1 ELSE 0
    END) AS init_first48,
    MAX(CASE
      WHEN p.starttime BETWEEN TIMESTAMP_SUB(dha.dischtime, INTERVAL 12 HOUR) AND dha.dischtime
      THEN 1 ELSE 0
    END) AS init_last12
  FROM
    diabetic_hf_admissions dha
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON dha.hadm_id = p.hadm_id
  WHERE
    -- Only consider our four classes
    (
      LOWER(p.drug) LIKE '%insulin%'
      OR LOWER(p.drug) LIKE '%metformin%'
      OR LOWER(p.drug) LIKE '%glipizide%'
      OR LOWER(p.drug) LIKE '%glyburide%'
      OR LOWER(p.drug) LIKE '%glimepiride%'
      OR LOWER(p.drug) LIKE '%olol%'
      OR LOWER(p.drug) LIKE '%pril%'
      OR LOWER(p.drug) LIKE '%sartan%'
      OR LOWER(p.drug) LIKE '%sacubitril%'
      OR LOWER(p.drug) LIKE '%furosemide%'
      OR LOWER(p.drug) LIKE '%bumetanide%'
      OR LOWER(p.drug) LIKE '%torsemide%'
    )
  GROUP BY
    dha.hadm_id,
    drug_class
  HAVING
    drug_class IS NOT NULL
),
rates AS (
  -- Compute rates per drug class
  SELECT
    drug_class,
    COUNTIF(init_first48 = 1) AS n_first48,
    COUNTIF(init_last12 = 1)   AS n_last12
  FROM med_inits
  GROUP BY drug_class
),
final AS (
  SELECT
    r.drug_class,
    ROUND(100.0 * r.n_first48 / cc.total_admissions, 1) AS first48_pct,
    ROUND(100.0 * r.n_last12  / cc.total_admissions, 1) AS last12_pct,
    ROUND(
      100.0 * r.n_first48 / cc.total_admissions
      - 100.0 * r.n_last12  / cc.total_admissions,
      1
    ) AS net_change_pct
  FROM rates r
  CROSS JOIN cohort_count cc
)
SELECT
  *
FROM final
ORDER BY drug_class;