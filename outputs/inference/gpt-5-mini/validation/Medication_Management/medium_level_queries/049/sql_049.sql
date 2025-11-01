WITH cohort AS (
  -- male admissions, age 66-76, LOS >= 72 hours, with both diabetes and heart failure diagnoses
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND a.hadm_id IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    AND EXISTS (
      -- diabetes diagnosis present for this admission
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        USING(icd_code, icd_version)
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      -- heart failure diagnosis present for this admission
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        USING(icd_code, icd_version)
      WHERE d.hadm_id = a.hadm_id
        AND (
          LOWER(dd.long_title) LIKE '%heart failure%'
          OR LOWER(dd.long_title) LIKE '%congestive heart failure%'
        )
    )
),

-- map prescriptions to antidiabetic classes and determine overlap with first 72h and final 24h windows
med_exposures AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- standardize drug name to lowercase for pattern matching
    LOWER(pr.drug) AS drug_l,
    CASE
      WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Biguanide (Metformin)'
      WHEN LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%'
        OR LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%tolbutamide%'
        OR LOWER(pr.drug) LIKE '%chlorpropamide%' THEN 'Sulfonylurea'
      WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%'
        OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%'
        OR LOWER(pr.drug) LIKE '%vildagliptin%' THEN 'DPP-4 inhibitor'
      WHEN LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%exenatide%'
        OR LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%dulaglutide%'
        OR LOWER(pr.drug) LIKE '%albiglutide%' THEN 'GLP-1 agonist'
      WHEN LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%'
        OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%'
        OR LOWER(pr.drug) LIKE '%sotagliflozin%' THEN 'SGLT2 inhibitor'
      WHEN LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinedione (TZD)'
      WHEN LOWER(pr.drug) LIKE '%repaglinide%' OR LOWER(pr.drug) LIKE '%nateglinide%' THEN 'Meglitinide'
      WHEN LOWER(pr.drug) LIKE '%acarbose%' OR LOWER(pr.drug) LIKE '%miglitol%' THEN 'Alpha-glucosidase inhibitor'
      ELSE NULL
    END AS drug_class,
    -- prescription interval
    pr.starttime AS rx_start,
    pr.stoptime AS rx_stop,
    -- compute window boundaries
    TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) AS first72_end,
    c.admittime AS first72_start,
    TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AS final24_start,
    c.dischtime AS final24_end
  FROM
    cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  -- we keep LEFT JOIN so that admissions with no prescriptions still appear (they will be filtered out later per class)
  WHERE
    pr.drug IS NOT NULL
),

-- for each hadm_id and drug_class, determine whether there was any exposure in each window
hadm_class_flags AS (
  SELECT
    me.hadm_id,
    me.drug_class,
    -- overlap logic: rx_start <= window_end AND (rx_stop IS NULL OR rx_stop >= window_start)
    MAX(
      CASE
        WHEN me.drug_class IS NOT NULL
         AND me.rx_start <= me.first72_end
         AND (me.rx_stop IS NULL OR me.rx_stop >= me.first72_start)
        THEN 1 ELSE 0 END
    ) AS exposed_first72,
    MAX(
      CASE
        WHEN me.drug_class IS NOT NULL
         AND me.rx_start <= me.final24_end
         AND (me.rx_stop IS NULL OR me.rx_stop >= me.final24_start)
        THEN 1 ELSE 0 END
    ) AS exposed_final24
  FROM
    med_exposures me
  GROUP BY
    me.hadm_id,
    me.drug_class
),

-- include classes that might not appear in prescriptions by unioning the mapped set (optional)
classes AS (
  SELECT DISTINCT drug_class FROM hadm_class_flags
  WHERE drug_class IS NOT NULL
),

-- aggregate counts and compute percentages
agg AS (
  SELECT
    c.drug_class,
    COUNT(DISTINCT CASE WHEN hcf.exposed_first72 = 1 THEN hcf.hadm_id END) AS n_first72,
    COUNT(DISTINCT CASE WHEN hcf.exposed_final24 = 1 THEN hcf.hadm_id END) AS n_final24
  FROM
    classes c
  LEFT JOIN
    hadm_class_flags hcf
    ON c.drug_class = hcf.drug_class
  GROUP BY
    c.drug_class
),

cohort_size AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_admissions FROM cohort
)

SELECT
  a.drug_class AS antidiabetic_class,
  ROUND( SAFE_DIVIDE(a.n_first72, cs.total_admissions) * 100, 1) AS pct_first72h,
  ROUND( SAFE_DIVIDE(a.n_final24, cs.total_admissions) * 100, 1) AS pct_final24h
FROM
  agg a,
  cohort_size cs
ORDER BY
  a.drug_class;