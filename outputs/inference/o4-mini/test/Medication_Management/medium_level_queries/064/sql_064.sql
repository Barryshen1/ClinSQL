WITH cohort AS (
  -- Step 1: basic inpatient cohort aged 71-81, male
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
),

dx_flags AS (
  -- Step 2: flag diabetes and acute heart failure per admission
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(CASE WHEN d.long_title LIKE 'E10%' 
                   OR d.long_title LIKE 'E11%' 
                   OR d.long_title LIKE 'E12%' 
                   OR d.long_title LIKE 'E13%' 
                   OR d.long_title LIKE 'E14%' 
             THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%acute%' 
                   AND LOWER(d.long_title) LIKE '%heart failure%'
             THEN 1 ELSE 0 END) AS has_acute_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      USING(icd_code, icd_version)
  GROUP BY
    di.subject_id, di.hadm_id
),

elig_admissions AS (
  -- Step 3: keep only admissions with both conditions
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime
  FROM
    cohort c
    JOIN dx_flags f
      ON c.subject_id = f.subject_id
     AND c.hadm_id = f.hadm_id
  WHERE
    f.has_diabetes = 1
    AND f.has_acute_hf = 1
),

meds AS (
  -- Step 4: pull prescriptions in the admission and classify drug class
  SELECT
    e.subject_id,
    e.hadm_id,
    p.starttime,
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'metformin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' 
        OR LOWER(p.drug) LIKE '%glyburide%' 
        OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' 
        OR LOWER(p.drug) LIKE '%saxagliptin%' 
        OR LOWER(p.drug) LIKE '%linagliptin%' 
        OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'dpp4'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' 
        OR LOWER(p.drug) LIKE '%dapagliflozin%' 
        OR LOWER(p.drug) LIKE '%canagliflozin%' THEN 'sglt2'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' 
        OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'thiazolidinedione'
      ELSE NULL
    END AS drug_class
  FROM
    elig_admissions e
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON e.subject_id = p.subject_id
     AND e.hadm_id = p.hadm_id
  WHERE
    p.starttime BETWEEN e.admittime AND e.dischtime
    AND LOWER(p.drug) IS NOT NULL
),

first_exposure AS (
  -- Step 5: find first starttime per admission and class
  SELECT
    subject_id,
    hadm_id,
    drug_class,
    MIN(starttime) AS first_time
  FROM
    meds
  WHERE
    drug_class IS NOT NULL
  GROUP BY
    subject_id, hadm_id, drug_class
),

flags AS (
  -- Step 6: flag first exposures in first 72h vs last 48h
  SELECT
    fe.subject_id,
    fe.hadm_id,
    fe.drug_class,
    fe.first_time,
    CASE WHEN fe.first_time <= e.admittime + INTERVAL 72 HOUR THEN 1 ELSE 0 END AS in_first_72h,
    CASE WHEN fe.first_time >= e.dischtime - INTERVAL 48 HOUR THEN 1 ELSE 0 END AS in_last_48h
  FROM
    first_exposure fe
    JOIN elig_admissions e
      USING(subject_id, hadm_id)
),

agg AS (
  -- Step 7: aggregate counts and compute rates
  SELECT
    drug_class,
    SUM(in_first_72h) AS count_first_72h,
    SUM(in_last_48h) AS count_last_48h,
    COUNT(DISTINCT hadm_id) AS admissions_with_class
  FROM
    flags
  GROUP BY
    drug_class
),

cohort_size AS (
  -- total number of matched admissions in cohort
  SELECT
    COUNT(DISTINCT hadm_id) AS total_admissions
  FROM
    elig_admissions
)

SELECT
  a.drug_class,
  SAFE_DIVIDE(a.count_first_72h, c.total_admissions) * 100 AS pct_initiated_first_72h,
  SAFE_DIVIDE(a.count_last_48h, c.total_admissions) * 100 AS pct_initiated_last_48h
FROM
  agg a
  CROSS JOIN cohort_size c
ORDER BY
  drug_class;