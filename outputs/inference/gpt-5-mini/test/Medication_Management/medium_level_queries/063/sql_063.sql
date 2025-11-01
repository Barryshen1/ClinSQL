WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    -- ensure valid admission times
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- require both diabetes AND heart failure diagnoses for the same admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
        USING (icd_code, icd_version)
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(ddi.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
        USING (icd_code, icd_version)
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(ddi.long_title) LIKE '%heart failure%'
    )
),

-- Identify first-in-admission starttime per hadm and medication class
med_first_start AS (
  SELECT
    c.hadm_id,
    CASE
      WHEN LOWER(r.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN (
        -- oral antidiabetic keywords (common drugs)
        LOWER(r.drug) LIKE '%metformin%'
        OR LOWER(r.drug) LIKE '%glipizide%'
        OR LOWER(r.drug) LIKE '%glyburide%'
        OR LOWER(r.drug) LIKE '%glimepiride%'
        OR LOWER(r.drug) LIKE '%gliclazide%'
        OR LOWER(r.drug) LIKE '%glibenclamide%'
        OR LOWER(r.drug) LIKE '%repaglinide%'
        OR LOWER(r.drug) LIKE '%nateglinide%'
        OR LOWER(r.drug) LIKE '%acarbose%'
        OR LOWER(r.drug) LIKE '%miglitol%'
        OR LOWER(r.drug) LIKE '%pioglitazone%'
        OR LOWER(r.drug) LIKE '%rosiglitazone%'
        OR LOWER(r.drug) LIKE '%sitagliptin%'
        OR LOWER(r.drug) LIKE '%saxagliptin%'
        OR LOWER(r.drug) LIKE '%linagliptin%'
        OR LOWER(r.drug) LIKE '%alogliptin%'
        OR LOWER(r.drug) LIKE '%vildagliptin%'
        OR LOWER(r.drug) LIKE '%canagliflozin%'
        OR LOWER(r.drug) LIKE '%dapagliflozin%'
        OR LOWER(r.drug) LIKE '%empagliflozin%'
        OR LOWER(r.drug) LIKE '%ertugliflozin%'
      )
      AND LOWER(r.drug) NOT LIKE '%insulin%'
      THEN 'Oral'
      ELSE NULL
    END AS med_class,
    MIN(r.starttime) AS first_starttime
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` r
      ON c.hadm_id = r.hadm_id
  WHERE
    r.starttime IS NOT NULL
    -- filter to rows that match either insulin OR oral list (avoid other meds)
    AND (
      LOWER(r.drug) LIKE '%insulin%'
      OR LOWER(r.drug) LIKE '%metformin%'
      OR LOWER(r.drug) LIKE '%glipizide%'
      OR LOWER(r.drug) LIKE '%glyburide%'
      OR LOWER(r.drug) LIKE '%glimepiride%'
      OR LOWER(r.drug) LIKE '%gliclazide%'
      OR LOWER(r.drug) LIKE '%glibenclamide%'
      OR LOWER(r.drug) LIKE '%repaglinide%'
      OR LOWER(r.drug) LIKE '%nateglinide%'
      OR LOWER(r.drug) LIKE '%acarbose%'
      OR LOWER(r.drug) LIKE '%miglitol%'
      OR LOWER(r.drug) LIKE '%pioglitazone%'
      OR LOWER(r.drug) LIKE '%rosiglitazone%'
      OR LOWER(r.drug) LIKE '%sitagliptin%'
      OR LOWER(r.drug) LIKE '%saxagliptin%'
      OR LOWER(r.drug) LIKE '%linagliptin%'
      OR LOWER(r.drug) LIKE '%alogliptin%'
      OR LOWER(r.drug) LIKE '%vildagliptin%'
      OR LOWER(r.drug) LIKE '%canagliflozin%'
      OR LOWER(r.drug) LIKE '%dapagliflozin%'
      OR LOWER(r.drug) LIKE '%empagliflozin%'
      OR LOWER(r.drug) LIKE '%ertugliflozin%'
    )
  GROUP BY
    c.hadm_id,
    med_class
  HAVING med_class IS NOT NULL
),

-- For each hadm and med_class, determine whether the first start falls in early or final windows
med_flags AS (
  SELECT
    m.hadm_id,
    m.med_class,
    m.first_starttime,
    c.admittime,
    c.dischtime,
    -- first 12 hours window (inclusive)
    CASE
      WHEN m.first_starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR) THEN 1
      ELSE 0
    END AS initiated_first12h,
    -- final 72 hours pre-discharge (inclusive)
    CASE
      WHEN m.first_starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime THEN 1
      ELSE 0
    END AS initiated_final72h
  FROM
    med_first_start m
    JOIN cohort c USING (hadm_id)
),

-- Aggregate counts per med class
agg AS (
  SELECT
    med_class,
    COUNT(DISTINCT CASE WHEN initiated_first12h = 1 THEN hadm_id END) AS cnt_first12h,
    COUNT(DISTINCT CASE WHEN initiated_final72h = 1 THEN hadm_id END) AS cnt_final72h
  FROM med_flags
  GROUP BY med_class
),

-- Denominator: total admissions in the cohort
denom AS (
  SELECT COUNT(*) AS total_admissions
  FROM cohort
)

SELECT
  a.med_class,
  a.cnt_first12h AS first12h_initiations,
  a.cnt_final72h AS final72h_initiations,
  d.total_admissions AS denominator,
  ROUND(100.0 * a.cnt_first12h / d.total_admissions, 2) AS pct_first12h,
  ROUND(100.0 * a.cnt_final72h / d.total_admissions, 2) AS pct_final72h,
  ROUND(100.0 * (a.cnt_first12h - a.cnt_final72h) / d.total_admissions, 2) AS pct_point_difference_first_minus_final
FROM
  agg a
  CROSS JOIN denom d
ORDER BY
  med_class;