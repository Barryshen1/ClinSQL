WITH acs_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.gender, p.anchor_age, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id
   AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND (
      -- ICD-based ACS definition via text
      LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
      OR LOWER(dd.long_title) LIKE '%unstable angina%'
      OR LOWER(dd.long_title) LIKE '%acute ischemic heart%'
      OR (di.icd_version = 9 AND di.icd_code LIKE '410%')
      OR (di.icd_version = 9 AND di.icd_code LIKE '411%')
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I21%')
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I22%')
      OR (di.icd_version = 10 AND di.icd_code = 'I20.0')
    )
),
troponin_first AS (
  SELECT
    acs.subject_id,
    acs.hadm_id,
    l.charttime,
    l.valuenum
  FROM acs_admissions acs
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON acs.subject_id = l.subject_id
   AND acs.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE dl.label LIKE '%Troponin T%'
    AND l.valuenum IS NOT NULL
    AND l.charttime IS NOT NULL
),
first_measurement AS (
  SELECT
    subject_id,
    hadm_id,
    valuenum AS troponin_t_value
  FROM (
    SELECT
      subject_id,
      hadm_id,
      valuenum,
      charttime,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
    FROM troponin_first
  ) t
  WHERE rn = 1
),
categorized AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    acs.hospital_expire_flag,
    CASE
      WHEN f.troponin_t_value <= 0.04 THEN 'Normal'
      WHEN f.troponin_t_value > 0.04 AND f.troponin_t_value <= 0.1 THEN 'Borderline'
      WHEN f.troponin_t_value > 0.1 THEN 'Elevated'
    END AS troponin_category
  FROM first_measurement f
  JOIN acs_admissions acs
    ON f.subject_id = acs.subject_id
   AND f.hadm_id = acs.hadm_id
)
SELECT
  troponin_category,
  COUNT(*) AS admissions_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percent_of_admissions,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS mortality_rate_percent
FROM categorized
GROUP BY troponin_category
ORDER BY troponin_category;