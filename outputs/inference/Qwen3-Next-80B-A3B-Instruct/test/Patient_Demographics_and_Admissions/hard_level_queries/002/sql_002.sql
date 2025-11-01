WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    a.insurance,
    a.admission_location,
    d.icd_code,
    d.icd_version,
    d.seq_num,
    did.long_title
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE
    d.seq_num = 1
    AND p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND UPPER(a.admission_location) LIKE '%EMERGENCY%'
    AND LOWER(did.long_title) LIKE '%pneumonia%'
),
indexed_admissions AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    first_admissions
)
SELECT
  COUNT(*) AS total_index_admissions
FROM
  indexed_admissions
WHERE
  rn = 1
  AND (anchor_age + EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 77 AND 87;