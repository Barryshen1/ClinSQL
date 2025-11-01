WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
         AND d.icd_version = 10
         AND d.seq_num = 1
         AND d.icd_code LIKE 'I21%'
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
),

troponin_item AS (
  -- Identify the itemid(s) for high-sensitivity troponin T
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%troponin t%'
    AND LOWER(label) LIKE '%high-sensitivity%'
),

first_troponin AS (
  -- For each admission, find the first troponin measurement
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM
    cohort
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      USING (subject_id, hadm_id)
    JOIN troponin_item ti
      USING (itemid)
  WHERE
    le.valuenum IS NOT NULL
)

SELECT
  CASE
    WHEN ft.valuenum <= 0.014 THEN 'Normal (≤0.014)'
    WHEN ft.valuenum <= 0.052 THEN 'Borderline (0.015–0.052)'
    ELSE 'Myocardial Injury (>0.052)'
  END AS troponin_category,
  COUNT(*) AS n_patients,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_cohort
FROM
  first_troponin ft
WHERE
  ft.rn = 1
GROUP BY
  troponin_category
ORDER BY
  troponin_category;