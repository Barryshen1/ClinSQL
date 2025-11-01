WITH upper_gi_bleed_codes AS (
  -- Define ICD codes for upper GI bleed (example: ICD-9 578.x or ICD-10 K92.x)
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code LIKE '578.%') OR
    (icd_version = 10 AND icd_code LIKE 'K92.%')
),

filtered_patients AS (
  -- Filter for 54-year-old females
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age = 54
),

primary_diagnosis_gi_bleed AS (
  -- Get admissions with primary diagnosis of upper GI bleed
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN upper_gi_bleed_codes c
    ON d.icd_code = c.icd_code
  WHERE
    d.seq_num = 1 AND  -- Primary diagnosis
    a.subject_id IN (SELECT subject_id FROM filtered_patients) AND
    a.dischtime IS NOT NULL  -- Exclude ongoing admissions
)

-- Calculate LOS and find the maximum
SELECT
  MAX(DATETIME_DIFF(dischtime, admittime, DAY)) AS max_los_days
FROM primary_diagnosis_gi_bleed;