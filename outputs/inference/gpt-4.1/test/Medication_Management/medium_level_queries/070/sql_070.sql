WITH cohort AS (
  -- Select female inpatients aged 68-78 with T2DM and HF
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- Age at admission: anchor_age is age at anchor_year, admission is in anchor_year
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 68 AND 78
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND (
            -- T2DM ICD-10: E11.x, ICD-9: 250.x0/250.x2
            (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E11'))
            OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250[0-9][02]'))
          )
      )
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND (
            -- HF ICD-10: I50.x, ICD-9: 428.x
            (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50'))
            OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
          )
      )
),

drug_classes AS (
  -- Map drugs to classes
  SELECT 'Metformin' AS drug_class, 'metformin' AS drug_name UNION ALL
  SELECT 'Sulfonylureas', 'glipizide' UNION ALL
  SELECT 'Sulfonylureas', 'glyburide' UNION ALL
  SELECT 'Sulfonylureas', 'glimepiride' UNION ALL
  SELECT 'Sulfonylureas', 'tolbutamide' UNION ALL
  SELECT 'Sulfonylureas', 'chlorpropamide' UNION ALL
  SELECT 'DPP-4 inhibitors', 'sitagliptin' UNION ALL
  SELECT 'DPP-4 inhibitors', 'linagliptin' UNION ALL
  SELECT 'DPP-4 inhibitors', 'saxagliptin' UNION ALL
  SELECT 'DPP-4 inhibitors', 'alogliptin' UNION ALL
  SELECT 'SGLT2 inhibitors', 'canagliflozin' UNION ALL
  SELECT 'SGLT2 inhibitors', 'dapagliflozin' UNION ALL
  SELECT 'SGLT2 inhibitors', 'empagliflozin' UNION ALL
  SELECT 'SGLT2 inhibitors', 'ertugliflozin'
),

presc_window AS (
  -- For each admission, drug class, and time window, flag exposure
  SELECT
    c.hadm_id,
    dc.drug_class,
    -- First 48h window
    MAX(CASE WHEN
      LOWER(pr.drug) = dc.drug_name
      AND pr.starttime >= c.admittime
      AND pr.starttime < DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
      THEN 1 ELSE 0 END) AS first48h_exposed,
    -- Last 12h window
    MAX(CASE WHEN
      LOWER(pr.drug) = dc.drug_name
      AND pr.starttime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
      AND pr.starttime < c.dischtime
      THEN 1 ELSE 0 END) AS last12h_exposed
  FROM
    cohort c
    CROSS JOIN drug_classes dc
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON pr.hadm_id = c.hadm_id
  GROUP BY
    c.hadm_id, dc.drug_class
),

agg AS (
  -- Aggregate to drug class per admission (any drug in class)
  SELECT
    hadm_id,
    drug_class,
    MAX(first48h_exposed) AS first48h_exposed,
    MAX(last12h_exposed) AS last12h_exposed
  FROM presc_window
  GROUP BY hadm_id, drug_class
),

prevalence AS (
  -- Calculate prevalence per drug class and window
  SELECT
    drug_class,
    COUNT(DISTINCT hadm_id) AS n_admissions,
    SUM(first48h_exposed) AS n_first48h,
    SUM(last12h_exposed) AS n_last12h
  FROM agg
  GROUP BY drug_class
),

final AS (
  SELECT
    drug_class,
    n_admissions,
    ROUND(100.0 * n_first48h / n_admissions, 1) AS prevalence_first48h_pct,
    ROUND(100.0 * n_last12h / n_admissions, 1) AS prevalence_last12h_pct,
    ROUND(100.0 * (n_last12h - n_first48h) / n_admissions, 1) AS net_pct_point_change
  FROM prevalence
)

SELECT
  drug_class,
  prevalence_first48h_pct,
  prevalence_last12h_pct,
  net_pct_point_change
FROM final
ORDER BY drug_class;