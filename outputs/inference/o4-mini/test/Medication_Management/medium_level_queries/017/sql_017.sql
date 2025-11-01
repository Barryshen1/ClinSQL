WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.subject_id = adm.subject_id
     AND icu.hadm_id    = adm.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
    -- require female age 37–47
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 37 AND 47
    -- ICU LOS ≥ 6 days (~144h)
    AND icu.los >= 6
    -- require both diabetes and heart failure diagnoses in this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = icu.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = icu.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),

-- classify prescriptions into drug classes
meds AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%'       OR LOWER(p.drug) LIKE '%insulin%'       THEN 'antidiabetic'
      WHEN LOWER(p.drug) LIKE '%metoprolol%'      OR LOWER(p.drug) LIKE '%propranolol%'    THEN 'beta-blocker'
      WHEN LOWER(p.drug) LIKE '%lisinopril%'      OR LOWER(p.drug) LIKE '%losartan%'       OR LOWER(p.drug) LIKE '%sacubitril%'    THEN 'ACEi/ARB/ARNI'
      WHEN LOWER(p.drug) LIKE '%furosemide%'      OR LOWER(p.drug) LIKE '%bumetanide%'     OR LOWER(p.drug) LIKE '%torsemide%'     THEN 'loop diuretic'
      ELSE NULL
    END AS drug_class,
    p.starttime
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON c.subject_id = p.subject_id
     AND c.hadm_id    = p.hadm_id
  WHERE
    -- only keep prescriptions that match one of our classes
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%'       OR LOWER(p.drug) LIKE '%insulin%'       THEN 1
      WHEN LOWER(p.drug) LIKE '%metoprolol%'      OR LOWER(p.drug) LIKE '%propranolol%'    THEN 1
      WHEN LOWER(p.drug) LIKE '%lisinopril%'      OR LOWER(p.drug) LIKE '%losartan%'       OR LOWER(p.drug) LIKE '%sacubitril%'    THEN 1
      WHEN LOWER(p.drug) LIKE '%furosemide%'      OR LOWER(p.drug) LIKE '%bumetanide%'     OR LOWER(p.drug) LIKE '%torsemide%'     THEN 1
      ELSE 0
    END = 1
),

-- determine exposure flags per patient, stay, drug_class
exposures AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    drug_class,
    MAX(IF(starttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 72 HOUR), 1, 0)) AS first_72h_flag,
    MAX(IF(starttime BETWEEN TIMESTAMP_SUB(outtime, INTERVAL 72 HOUR) AND outtime,       1, 0)) AS final_72h_flag
  FROM
    meds
  GROUP BY
    subject_id, hadm_id, stay_id, drug_class
),

-- count summary per drug class
summary AS (
  SELECT
    drug_class,
    COUNT(1) AS n_cohort,
    SUM(first_72h_flag)                                       AS n_first,
    SUM(final_72h_flag)                                       AS n_final,
    SUM(CASE WHEN first_72h_flag=1 AND final_72h_flag=1 THEN 1 ELSE 0 END) AS n_continued,
    SUM(CASE WHEN first_72h_flag=0 AND final_72h_flag=1 THEN 1 ELSE 0 END) AS n_initiated,
    SUM(CASE WHEN first_72h_flag=1 AND final_72h_flag=0 THEN 1 ELSE 0 END) AS n_discontinued
  FROM
    exposures
  GROUP BY
    drug_class
),

-- compute total cohort size for percentages
total_cohort AS (
  SELECT COUNT(DISTINCT stay_id) AS total_n
  FROM cohort
)

SELECT
  s.drug_class,
  total_n,
  s.n_first,
  ROUND(100.0 * s.n_first / total_n, 1)   AS pct_first,
  s.n_final,
  ROUND(100.0 * s.n_final / total_n, 1)   AS pct_final,
  s.n_continued,
  s.n_initiated,
  s.n_discontinued
FROM
  summary s
  CROSS JOIN total_cohort
ORDER BY
  drug_class;