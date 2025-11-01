WITH candidate AS (
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
   AND di.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = di.icd_code
   AND dd.icd_version = di.icd_version
  WHERE LOWER(dd.long_title) LIKE '%osteomyelitis%'
    -- Female
    AND p.gender = 'F'
    -- Age 85-95 (year-based approximation)
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 85 AND 95
    -- Medicare
    AND LOWER(a.insurance) LIKE '%medicare%'
    -- Principal diagnosis is osteomyelitis (seq_num = 1 already enforced)
    AND di.seq_num = 1
    -- Transferred from another hospital
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.transfers` AS t
      WHERE t.subject_id = a.subject_id
        AND t.hadm_id = a.hadm_id
        AND LOWER(t.eventtype) LIKE '%transfer%'
    )
)
SELECT
  COUNT(*) AS index_admissions_meeting_criteria
FROM (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM candidate
) AS numbered
WHERE rn = 1;