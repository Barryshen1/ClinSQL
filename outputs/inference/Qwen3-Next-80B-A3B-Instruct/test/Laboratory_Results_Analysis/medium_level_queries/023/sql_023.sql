WITH acs_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND (
      LOWER(d_icd.long_title) LIKE '%acute coronary syndrome%'
      OR LOWER(d_icd.long_title) LIKE '%myocardial infarction%'
      OR d_icd.icd_code LIKE 'I21%'  -- ICD-10 MI
      OR d_icd.icd_code LIKE 'I24%'  -- ICD-10 other acute ischemic heart disease
      OR d_icd.icd_code LIKE 'I25.2%' -- ICD-10 chronic ischemic heart disease with acute event
      OR d.icd_code LIKE '410%'       -- ICD-9 MI
      OR d.icd_code LIKE '411%'       -- ICD-9 other acute ischemic heart disease
    )
),
first_troponin_t AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum >= 0  -- exclude implausible negative values
)
SELECT
  CASE
    WHEN ft.valuenum <= 0.04 THEN 'Normal (≤0.04)'
    WHEN ft.valuenum > 0.04 AND ft.valuenum <= 0.1 THEN 'Borderline (>0.04–0.1)'
    WHEN ft.valuenum > 0.1 THEN 'Elevated (>0.1)'
    ELSE 'Unknown'
  END AS troponin_category,
  COUNT(*) AS admission_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent_of_admissions,
  ROUND(100.0 * SUM(CAST(aa.hospital_expire_flag AS FLOAT64)) / COUNT(*), 2) AS in_hospital_mortality_rate_percent
FROM acs_admissions aa
INNER JOIN first_troponin_t ft ON aa.hadm_id = ft.hadm_id
WHERE ft.rn = 1
GROUP BY troponin_category
ORDER BY troponin_category;