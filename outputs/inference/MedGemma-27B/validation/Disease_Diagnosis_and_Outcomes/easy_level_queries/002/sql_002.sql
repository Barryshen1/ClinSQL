WITH AKI_Admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    p.gender,
    p.anchor_age,
    dd.long_title AS diagnosis
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND d.icd_code LIKE 'N17%' -- AKI ICD-10 codes
),
Hospital_LOS AS (
  SELECT
    hadm_id,
    -- Calculate hospital length of stay in days
    -- Use COALESCE to handle cases where dischtime is NULL (patient still admitted)
    -- Use CASE to handle cases where deathtime is NULL (patient discharged)
    -- Use CASE to handle cases where deathtime is not NULL (patient died)
    CASE
      WHEN dischtime IS NOT NULL THEN TIMESTAMP_DIFF(dischtime, admittime, DAY)
      WHEN deathtime IS NOT NULL THEN TIMESTAMP_DIFF(deathtime, admittime, DAY)
      ELSE NULL -- Or handle as ongoing admission if needed
    END AS hospital_los
  FROM AKI_Admissions
)
SELECT
  PERCENTILE_CONT(0.75, hospital_los) AS percentile_75_los
FROM Hospital_LOS
WHERE
  hospital_los IS NOT NULL;