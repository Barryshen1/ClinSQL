WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND LOWER(a.admission_location) LIKE '%emergency%'
    -- Principal diagnosis only
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code = '7802')
      OR (d.icd_version = 10 AND d.icd_code = 'R55')
    )
    -- Age at admission between 62 and 72 inclusive
    AND (
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
    ) BETWEEN 62 AND 72
)
SELECT COUNT(*) AS num_index_admissions
FROM cohort
WHERE rn = 1;