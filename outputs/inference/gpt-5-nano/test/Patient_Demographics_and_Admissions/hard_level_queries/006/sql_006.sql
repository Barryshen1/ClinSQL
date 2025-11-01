WITH cohort AS (
  SELECT
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id
   AND a.hadm_id = di.hadm_id
   AND di.seq_num = 1  -- principal diagnosis
  WHERE
    -- Female
    p.gender = 'F'
    -- Medicare insurance
    AND LOWER(a.insurance) LIKE '%medicare%'
    -- Age at admission between 36 and 46 inclusive
    AND (
      CAST(p.anchor_age AS INT64) +
      (EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64))
    ) BETWEEN 36 AND 46
    -- Hemorrhagic stroke principal dx
    AND (
      (di.icd_version = 9  AND di.icd_code IN ('430','431','432')) OR
      (di.icd_version = 10 AND di.icd_code IN ('I60','I61','I62'))
    )
    -- Admitted via transfer from another hospital
    AND (
      a.admission_type = 'TRANSFER'
      OR EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.transfers` AS t
        WHERE t.subject_id = a.subject_id
          AND t.hadm_id = a.hadm_id
          AND LOWER(t.eventtype) LIKE '%transfer%'
      )
    )
)
SELECT
  COUNT(DISTINCT hadm_id) AS index_admissions
FROM cohort;