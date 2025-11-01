WITH ami_admissions AS (
  -- Identify admissions for AMI (ICD-9 410.*, ICD-10 I21.*, I22.*), female, age 64-74
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    LOWER(p.gender) = 'female'
    AND p.anchor_age BETWEEN 64 AND 74
    AND d.seq_num = 1
    AND (
      -- ICD-9 AMI
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^410'))
      -- ICD-10 AMI
      OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I21|^I22'))
    )
),

troponin_itemids AS (
  -- Find itemids for high-sensitivity troponin T
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%troponin t%'
    AND LOWER(label) LIKE '%high%'
),

index_troponin AS (
  -- For each qualifying admission, get the first high-sensitivity troponin T result
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    l.charttime,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN troponin_itemids t
      ON l.itemid = t.itemid
  WHERE
    l.valuenum IS NOT NULL
),

cohort_with_troponin AS (
  -- Join AMI admissions with their index troponin T
  SELECT
    a.subject_id,
    a.hadm_id,
    a.gender,
    a.anchor_age,
    i.valuenum AS troponin_t,
    i.charttime
  FROM
    ami_admissions a
    JOIN index_troponin i
      ON a.subject_id = i.subject_id
      AND a.hadm_id = i.hadm_id
  WHERE
    i.rn = 1
)

SELECT
  CASE
    WHEN troponin_t <= 0.014 THEN 'Normal (≤0.014)'
    WHEN troponin_t BETWEEN 0.015 AND 0.052 THEN 'Borderline (0.015–0.052)'
    WHEN troponin_t > 0.052 THEN 'Myocardial Injury (>0.052)'
    ELSE 'Unknown'
  END AS troponin_category,
  COUNT(*) AS n_admissions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percent_of_total
FROM
  cohort_with_troponin
GROUP BY
  troponin_category
ORDER BY
  percent_of_total DESC;