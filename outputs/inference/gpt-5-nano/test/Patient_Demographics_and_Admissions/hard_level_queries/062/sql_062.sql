WITH eligible AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  WHERE LOWER(a.insurance) = 'medicare'
    AND a.edregtime IS NOT NULL                      -- admitted from the ED
    AND di.seq_num = 1
    AND di.icd_code = 'K81.0'                         -- acute cholecystitis
    AND (p.gender = 'F' OR p.gender = 'Female')       -- female
    AND p.anchor_age BETWEEN 38 AND 48
),
indexed AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM eligible
)
SELECT COUNT(*) AS index_admissions
FROM indexed
WHERE rn = 1;