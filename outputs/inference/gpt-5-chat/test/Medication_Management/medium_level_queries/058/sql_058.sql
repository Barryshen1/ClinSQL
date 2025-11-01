WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- Diagnoses: both T2DM and HF
  JOIN (
    SELECT hadm_id,
      COUNTIF(t2dm) AS t2dm_count,
      COUNTIF(hf) AS hf_count
    FROM (
      SELECT
        di.hadm_id,
        -- type 2 diabetes flags
        CASE
          WHEN di.icd_version = 9 AND di.icd_code LIKE '250%' AND RIGHT(di.icd_code,1) IN ('0','2') THEN TRUE
          WHEN di.icd_version = 10 AND di.icd_code LIKE 'E11%' THEN TRUE
        END AS t2dm,
        -- heart failure flags
        CASE
          WHEN di.icd_version = 9 AND di.icd_code LIKE '428%' THEN TRUE
          WHEN di.icd_version = 10 AND di.icd_code LIKE 'I50%' THEN TRUE
        END AS hf
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    )
    GROUP BY hadm_id
    HAVING t2dm_count > 0 AND hf_count > 0
  ) dx
    ON a.hadm_id = dx.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
),
drug_classes AS (
  SELECT
    hadm_id,
    CASE
      WHEN UPPER(drug) LIKE '%METFORMIN%' THEN 'Biguanide'
      WHEN UPPER(drug) LIKE '%GLIPIZIDE%' OR UPPER(drug) LIKE '%GLYBURIDE%' OR UPPER(drug) LIKE '%GLIMEPIRIDE%' THEN 'Sulfonylurea'
      WHEN UPPER(drug) LIKE '%SITAGLIPTIN%' OR UPPER(drug) LIKE '%LINAGLIPTIN%' OR UPPER(drug) LIKE '%ALOGLIPTIN%' OR UPPER(drug) LIKE '%SAXAGLIPTIN%' THEN 'DPP4 inhibitor'
      WHEN UPPER(drug) LIKE '%DAPAGLIFLOZIN%' OR UPPER(drug) LIKE '%EMPAGLIFLOZIN%' OR UPPER(drug) LIKE '%CANAGLIFLOZIN%' THEN 'SGLT2 inhibitor'
      WHEN UPPER(drug) LIKE '%LIRAGLUTIDE%' OR UPPER(drug) LIKE '%SEMAGLUTIDE%' OR UPPER(drug) LIKE '%EXENATIDE%' OR UPPER(drug) LIKE '%DULAGLUTIDE%' THEN 'GLP-1 RA'
      WHEN UPPER(drug) LIKE '%INSULIN%' THEN 'Insulin'
    END AS drug_class,
    starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
),
first_initiations AS (
  SELECT
    c.hadm_id,
    dc.drug_class,
    MIN(dc.starttime) AS first_starttime,
    c.admittime,
    c.dischtime
  FROM cohort c
  JOIN drug_classes dc
    ON c.hadm_id = dc.hadm_id
  WHERE dc.drug_class IS NOT NULL
  GROUP BY c.hadm_id, dc.drug_class, c.admittime, c.dischtime
),
flags AS (
  SELECT
    fi.drug_class,
    CASE WHEN fi.first_starttime <= fi.admittime + INTERVAL 12 HOUR THEN 1 ELSE 0 END AS first12h,
    CASE WHEN fi.first_starttime >= fi.dischtime - INTERVAL 48 HOUR THEN 1 ELSE 0 END AS last48h
  FROM first_initiations fi
),
agg AS (
  SELECT
    drug_class,
    COUNT(DISTINCT CASE WHEN first12h = 1 THEN hadm_id END) AS num_first12h,
    COUNT(DISTINCT CASE WHEN last48h = 1 THEN hadm_id END) AS num_last48h
  FROM (
    SELECT fi.hadm_id, fi.drug_class,
      CASE WHEN fi.first_starttime <= fi.admittime + INTERVAL 12 HOUR THEN 1 ELSE 0 END AS first12h,
      CASE WHEN fi.first_starttime >= fi.dischtime - INTERVAL 48 HOUR THEN 1 ELSE 0 END AS last48h
    FROM first_initiations fi
  )
  GROUP BY drug_class
),
denom AS (
  SELECT COUNT(DISTINCT hadm_id) AS denom
  FROM cohort
)
SELECT
  a.drug_class,
  ROUND(a.num_first12h / d.denom * 100, 1) AS rate_first12h_pct,
  ROUND(a.num_last48h / d.denom * 100, 1) AS rate_last48h_pct,
  ROUND(a.num_last48h / d.denom * 100 - a.num_first12h / d.denom * 100, 1) AS net_change_pp
FROM agg a
CROSS JOIN denom d
ORDER BY drug_class;