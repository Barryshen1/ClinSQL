WITH acs_admissions AS (
  -- Get admissions for male patients aged 79-89 with ACS diagnosis
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN physionet-data.mimiciv_3_1_hosp.patients p
      ON a.subject_id = p.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      ON a.hadm_id = d.hadm_id
    JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND (
      -- ICD-10 ACS codes
      (d.icd_version = 10 AND (
        LEFT(d.icd_code, 3) IN ('I20', 'I21', 'I22', 'I24')
      ))
      -- ICD-9 ACS codes
      OR (d.icd_version = 9 AND (
        LEFT(d.icd_code, 3) IN ('410', '411', '412')
      ))
    )
),
troponin_t_items AS (
  -- Find itemids for Troponin T
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE LOWER(label) LIKE '%troponin t%'
),
index_troponin AS (
  -- For each ACS admission, get the first Troponin T measurement
  SELECT
    la.subject_id,
    la.hadm_id,
    MIN(la.charttime) AS first_charttime
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents la
    JOIN troponin_t_items tti ON la.itemid = tti.itemid
    JOIN acs_admissions acs ON la.hadm_id = acs.hadm_id
  WHERE
    la.valuenum IS NOT NULL
  GROUP BY
    la.subject_id,
    la.hadm_id
),
troponin_values AS (
  -- Get the value of the first Troponin T measurement per admission
  SELECT
    la.subject_id,
    la.hadm_id,
    la.valuenum AS troponin_t_value
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents la
    JOIN index_troponin idx
      ON la.subject_id = idx.subject_id
      AND la.hadm_id = idx.hadm_id
      AND la.charttime = idx.first_charttime
    JOIN troponin_t_items tti ON la.itemid = tti.itemid
)
SELECT
  CASE
    WHEN troponin_t_value <= 0.04 THEN 'Normal (≤0.04)'
    WHEN troponin_t_value > 0.04 AND troponin_t_value <= 0.1 THEN 'Borderline (>0.04–0.1)'
    WHEN troponin_t_value > 0.1 THEN 'Elevated (>0.1)'
    ELSE 'Unknown'
  END AS troponin_t_category,
  COUNT(*) AS admission_count
FROM troponin_values
GROUP BY troponin_t_category
ORDER BY
  CASE troponin_t_category
    WHEN 'Normal (≤0.04)' THEN 1
    WHEN 'Borderline (>0.04–0.1)' THEN 2
    WHEN 'Elevated (>0.1)' THEN 3
    ELSE 4
  END;