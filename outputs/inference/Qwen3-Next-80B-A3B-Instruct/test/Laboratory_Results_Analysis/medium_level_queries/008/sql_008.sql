WITH acs_admissions AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    AND (
      LOWER(dicd.long_title) LIKE '%acute coronary syndrome%'
      OR LOWER(dicd.long_title) LIKE '%unstable angina%'
      OR LOWER(dicd.long_title) LIKE '%myocardial infarction%'
      OR LOWER(dicd.long_title) LIKE '%acute ischemic heart disease%'
    )
),
first_troponin_t AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
)
SELECT
  CASE
    WHEN ft.valuenum <= 0.04 THEN 'Normal/Minimal'
    WHEN ft.valuenum <= 0.1 THEN 'Borderline'
    WHEN ft.valuenum > 0.1 THEN 'Elevated'
    ELSE 'Unknown'
  END AS troponin_t_category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(100.0 * SUM(CASE WHEN aa.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS in_hospital_mortality_rate_percent
FROM acs_admissions aa
INNER JOIN first_troponin_t ft
  ON aa.hadm_id = ft.hadm_id
WHERE ft.rn = 1
GROUP BY troponin_t_category
ORDER BY troponin_t_category;