WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    ROW_NUMBER() OVER (
      PARTITION BY adm.subject_id
      ORDER BY adm.admittime
    ) AS admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    adm.admission_location = 'EMERGENCY ROOM'
    AND adm.insurance = 'Medicare'
    AND adm.dischtime IS NOT NULL
    AND pat.gender = 'F'
    AND diag.seq_num = 1  -- Principal diagnosis
    AND (
      (diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 3) IN ('430', '431', '432'))
      OR
      (diag.icd_version = 10 AND SUBSTR(diag.icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
    )
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year))
        BETWEEN 68 AND 78
)
SELECT COUNT(*) AS count_index_admissions
FROM cohort
WHERE admission_rank = 1;  -- First qualifying admission per patient;