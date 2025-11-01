WITH stroke_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
      AND a.hadm_id    = d.hadm_id
  WHERE
    p.gender       = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_location = 'EMERGENCY'
    AND a.insurance          = 'Medicare'
    AND a.dischtime IS NOT NULL
    AND d.seq_num = 1
    AND (
      -- ICD-9 hemorrhagic stroke codes
      (d.icd_version = 9 AND d.icd_code IN ('430','431','432'))
      OR
      -- ICD-10 hemorrhagic stroke codes
      (d.icd_version = 10
       AND (
         STARTS_WITH(d.icd_code, 'I60')
         OR STARTS_WITH(d.icd_code, 'I61')
         OR STARTS_WITH(d.icd_code, 'I62')
       )
      )
    )
),
first_strokes AS (
  -- Identify the first qualifying admission per patient
  SELECT
    subject_id,
    MIN(admittime) AS first_adm_time
  FROM
    stroke_adms
  GROUP BY
    subject_id
)
-- Count how many of those first admissions exist
SELECT
  COUNT(*) AS num_index_admissions
FROM
  first_strokes fs
  JOIN stroke_adms sa
    ON fs.subject_id = sa.subject_id
   AND fs.first_adm_time = sa.admittime;