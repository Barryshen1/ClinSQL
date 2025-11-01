WITH admissions_with_age AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM admissions_with_age a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    a.age = 70
    AND d.seq_num = 1
    AND (
      -- ICD-10 codes for upper GI bleeding (K25-K28 with hemorrhage, K92.0-K92.1)
      (d.icd_version = 10 AND (REGEXP_CONTAINS(d.icd_code, r'^K2[5678][0246]') OR d.icd_code IN ('K920', 'K921')))
      OR
      -- ICD-9 codes for upper GI bleeding (ulcers with hemorrhage, hematemesis, melena)
      (d.icd_version = 9 AND d.icd_code IN (
        '5310', '5312', '5314', '5316',  -- gastric ulcer
        '5320', '5322', '5324', '5326',  -- duodenal ulcer
        '5330', '5332', '5334', '5336',  -- peptic ulcer
        '5340', '5342', '5344', '5346',  -- gastrojejunal ulcer
        '5780', '5781'                   -- hematemesis, melena
      ))
    )
)
SELECT 
  PERCENTILE_CONT(los, 0.75) OVER() AS p75_los
FROM (
  SELECT 
    DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS los
  FROM filtered_admissions
  WHERE dischtime IS NOT NULL AND admittime IS NOT NULL
)
LIMIT 1;